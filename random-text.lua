obs = obslua

local SETTINGS_FILENAME = "random-text.settings.json"
local PROJECT_DIR = "random-text"
local AVAILABLE_LANGUAGES = { "en", "ru", "es", "fr" }
local LANG_KEYS = {
    "description", "options", "source",
    "animation_group", "sound_group",
    "with_animation", "remove_line",
    "time_to_display", "roll_delay", "deceleration",
    "play_sound", "sound_path",
    "get_random", "reset",
}

local SCRIPT_DIR = script_path()

-- ------------------------------------------------------------
-- Language

local Lang = {}
Lang.__index = Lang

function Lang.new(code)
    local self = setmetatable({}, Lang)
    self.code = code
    self.ok = false
    self.messages = {}

    local path = SCRIPT_DIR .. PROJECT_DIR .. "/lang/" .. code .. ".json"
    local f = io.open(path, "r")
    if not f then
        print("[random-text] lang file missing: " .. path)
        return self
    end
    local content = f:read("*a")
    f:close()

    if content == nil or content == "" then
        print("[random-text] lang file empty: " .. path)
        return self
    end

    local data = obs.obs_data_create_from_json(content)
    if data == nil then
        print("[random-text] lang file invalid JSON: " .. path)
        return self
    end

    local missing = {}
    for _, key in ipairs(LANG_KEYS) do
        local val = obs.obs_data_get_string(data, key)
        if val ~= nil and val ~= "" then
            self.messages[key] = val
        else
            table.insert(missing, key)
        end
    end
    obs.obs_data_release(data)

    if #missing > 0 then
        print("[random-text] lang '" .. code .. "' missing keys: " .. table.concat(missing, ", "))
    end

    self.ok = next(self.messages) ~= nil
    return self
end

function Lang:t(key)
    return self.messages[key] or key
end

local function load_lang(code)
    local l = Lang.new(code)
    if not l.ok and code ~= "en" then
        print("[random-text] falling back to 'en'")
        l = Lang.new("en")
    end
    return l
end

-- ------------------------------------------------------------
-- State

local Data = {
    props = nil,
    settings = nil,

    lang_code = "en",
    lang = nil,

    lines = {},
    source_name = "",

    with_animation = false,
    remove_line = false,
    deceleration = 50,
    roll_delay = 42,
    time_to_display = 2,

    play_sound = false,
    sound_path = "",
    media_source = nil,
    output_index = 63,
}

-- ------------------------------------------------------------
-- Hotkey

local hotkey_id = obs.OBS_INVALID_HOTKEY_ID

-- ------------------------------------------------------------
-- Helpers

local function split_lines(text)
    local t = {}
    for line in string.gmatch(text, "([^\r\n]+)") do
        if line:match("%S") then
            table.insert(t, line)
        end
    end
    return t
end

local function join_lines(lines)
    return table.concat(lines, "\n")
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- ------------------------------------------------------------
-- Persistence

local function save()
    if not Data.settings then
        return
    end
    local path = SCRIPT_DIR .. PROJECT_DIR .. "/" .. SETTINGS_FILENAME
    local content = obs.obs_data_get_json(Data.settings)
    local f, err = io.open(path, "w")
    if not f then
        print("can't save settings: " .. tostring(err))
        return
    end
    f:write(content)
    f:close()
end

local function load_persisted()
    local path = SCRIPT_DIR .. PROJECT_DIR .. "/" .. SETTINGS_FILENAME
    local f = io.open(path, "r")
    if not f then
        return
    end
    local content = f:read("*a")
    f:close()

    local data = obs.obs_data_create_from_json(content)
    if data ~= nil then
        local code = obs.obs_data_get_string(data, "lang")
        if code ~= nil and code ~= "" then
            Data.lang_code = code
            Data.lang = Lang.new(code)
        end
        obs.obs_data_release(data)
    end
end

-- ------------------------------------------------------------
-- Sound

local function play_sound()
    if Data.media_source == nil then
        Data.media_source = obs.obs_source_create_private(
            "ffmpeg_source", "Global Media Source", nil
        )
        obs.obs_source_set_monitoring_type(
            Data.media_source, obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT
        )
        obs.obs_set_output_source(Data.output_index, Data.media_source)
    end
    local s = obs.obs_data_create()
    obs.obs_data_set_string(s, "local_file", Data.sound_path)
    obs.obs_data_set_bool(s, "is_local_file", true)
    obs.obs_data_set_bool(s, "looping", false)
    obs.obs_data_set_bool(s, "restart_on_activate", false)
    obs.obs_source_update(Data.media_source, s)
    obs.obs_data_release(s)

    obs.obs_source_media_restart(Data.media_source)
end

-- ------------------------------------------------------------
-- Animation via timer (non-blocking)

local anim = {
    active = false,
    source = nil,
    pool = {},
    final_text = "",
    elapsed = 0,
    speed_mod = 1,
    deceleration = 0,
}

local function anim_stop()
    anim.active = false
    if anim.source ~= nil then
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, "text", anim.final_text)
        obs.obs_source_update(anim.source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(anim.source)
        anim.source = nil
    end
    anim.pool = {}
end

function anim_tick()
    if not anim.active then
        obs.remove_current_callback()
        return
    end

    local n = #anim.pool
    if n > 0 and anim.source ~= nil then
        local idx = math.random(n)
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, "text", anim.pool[idx])
        obs.obs_source_update(anim.source, settings)
        obs.obs_data_release(settings)
    end

    local sleep_time = Data.roll_delay / 1000
    local deceleration_default = Data.deceleration / 1000
    local current_sleep_time = sleep_time * (anim.speed_mod + anim.deceleration)
    anim.elapsed = anim.elapsed + current_sleep_time
    anim.deceleration = anim.deceleration + deceleration_default

    obs.remove_current_callback()

    if anim.elapsed >= Data.time_to_display then
        anim_stop()
        if Data.play_sound then
            play_sound()
        end
        return
    end

    local next_ms = math.max(1, math.floor(current_sleep_time * 1000))
    obs.timer_add(anim_tick, next_ms)
end

local function animate_selection(source, pool, final_text)
    anim_stop()
    anim.active = true
    anim.source = source
    anim.pool = pool
    anim.final_text = final_text
    anim.elapsed = 0
    anim.speed_mod = 1
    anim.deceleration = 0
    obs.timer_add(anim_tick, Data.roll_delay)
end

-- ------------------------------------------------------------
-- Core

local function update_text()
    local source = obs.obs_get_source_by_name(Data.source_name)
    if source == nil then
        return
    end

    local text = ""
    if #Data.lines > 0 then
        shuffle(Data.lines)
        if Data.remove_line then
            text = table.remove(Data.lines)
        else
            text = Data.lines[1]
        end
    end

    if Data.with_animation then
        local pool = {}
        for _, v in ipairs(Data.lines) do
            table.insert(pool, v)
        end
        table.insert(pool, text)
        -- animate_selection takes ownership of source reference
        animate_selection(source, pool, text)
    else
        local settings = obs.obs_data_create()
        obs.obs_data_set_string(settings, "text", text)
        obs.obs_source_update(source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(source)

        if Data.play_sound then
            play_sound()
        end
    end

    obs.obs_data_set_string(Data.settings, "text", join_lines(Data.lines))
    save()
end

-- ------------------------------------------------------------
-- Callbacks

local function on_get_random_click(props, prop)
    update_text()
    return Data.remove_line
end

local function on_get_random_hotkey_pressed(pressed)
    if pressed then
        update_text()
    end
end

local function on_clear_click(props, prop)
    Data.lines = {}
    if Data.settings ~= nil then
        obs.obs_data_set_string(Data.settings, "text", "")
        save()
    end
    return true
end

-- ------------------------------------------------------------
-- Script entry points

load_persisted()
Data.lang = load_lang(Data.lang_code)

function script_load(settings)
    math.randomseed(os.time())

    hotkey_id = obs.obs_hotkey_register_frontend(
        "get_random_text",
        Data.lang:t("get_random"),
        on_get_random_hotkey_pressed
    )
    local hotkey_save_array = obs.obs_data_get_array(settings, "get_random_text_hotkey")
    obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, "get_random_text_hotkey", hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

function script_unload()
    anim_stop()
    if Data.media_source ~= nil then
        obs.obs_source_release(Data.media_source)
        Data.media_source = nil
    end
end

function script_description()
    if Data.lang == nil then
        Data.lang = load_lang(Data.lang_code)
    end
    return Data.lang:t("description")
end

local PROP_LANG_MAP = {
    text = "options",
    source = "source",
    animation_group = "animation_group",
    sound_group = "sound_group",
    with_animation = "with_animation",
    remove_line = "remove_line",
    time_to_display = "time_to_display",
    roll_delay = "roll_delay",
    deceleration = "deceleration",
    play_sound = "play_sound",
    sound_path = "sound_path",
    button = "get_random",
    button2 = "reset",
}

function apply_lang_to_props(props)
    if props == nil or Data.lang == nil then return end
    for prop_name, key in pairs(PROP_LANG_MAP) do
        local prop = obs.obs_properties_get(props, prop_name)
        if prop ~= nil then
            obs.obs_property_set_description(prop, Data.lang:t(key))
        end
    end
end

function on_lang_changed(props, property, settings)
    local new_lang = obs.obs_data_get_string(settings, "lang")
    print("[random-text] lang changed -> " .. tostring(new_lang))
    if new_lang == nil or new_lang == "" then
        return false
    end
    if new_lang ~= Data.lang_code then
        Data.lang_code = new_lang
        Data.lang = load_lang(new_lang)
    end
    apply_lang_to_props(props)
    return true
end

function script_update(settings)
    Data.settings = settings

    local text = obs.obs_data_get_string(settings, "text")
    local lines = split_lines(text)
    shuffle(lines)
    Data.lines = lines

    Data.source_name = obs.obs_data_get_string(settings, "source")

    Data.with_animation = obs.obs_data_get_bool(settings, "with_animation")
    Data.remove_line = obs.obs_data_get_bool(settings, "remove_line")
    Data.deceleration = obs.obs_data_get_int(settings, "deceleration")
    Data.time_to_display = obs.obs_data_get_int(settings, "time_to_display")
    Data.roll_delay = obs.obs_data_get_int(settings, "roll_delay")

    Data.play_sound = obs.obs_data_get_bool(settings, "play_sound")
    Data.sound_path = obs.obs_data_get_string(settings, "sound_path")

    local new_lang = obs.obs_data_get_string(settings, "lang")
    if new_lang ~= nil and new_lang ~= "" and new_lang ~= Data.lang_code then
        Data.lang_code = new_lang
        Data.lang = load_lang(new_lang)
    end

    save()
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "text", "1. \n2. \n3. \n")

    obs.obs_data_set_default_bool(settings, "with_animation", false)
    obs.obs_data_set_default_bool(settings, "remove_line", false)
    obs.obs_data_set_default_int(settings, "roll_delay", 42)
    obs.obs_data_set_default_int(settings, "time_to_display", 2)
    obs.obs_data_set_default_int(settings, "deceleration", 50)

    obs.obs_data_set_default_string(
        settings, "sound_path",
        script_path() .. PROJECT_DIR .. "/alert.mp3"
    )

    obs.obs_data_set_default_string(settings, "lang", "en")
end

function script_properties()
    local props = obs.obs_properties_create()
    Data.props = props

    local l = obs.obs_properties_add_list(
        props, "lang", "Language",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING
    )
    for _, code in ipairs(AVAILABLE_LANGUAGES) do
        obs.obs_property_list_add_string(l, code, code)
    end
    obs.obs_property_set_modified_callback(l, on_lang_changed)

    obs.obs_properties_add_text(props, "text", Data.lang:t("options"), obs.OBS_TEXT_MULTILINE)

    local p = obs.obs_properties_add_list(
        props, "source", Data.lang:t("source"),
        obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING
    )
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local source_id = obs.obs_source_get_unversioned_id(source)
            if source_id == "text_gdiplus" or source_id == "text_ft2_source" then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(p, name, name)
            end
        end
        obs.source_list_release(sources)
    end

    local anim_props = obs.obs_properties_create()
    obs.obs_properties_add_bool(anim_props, "with_animation", Data.lang:t("with_animation"))
    obs.obs_properties_add_bool(anim_props, "remove_line", Data.lang:t("remove_line"))
    obs.obs_properties_add_int_slider(anim_props, "time_to_display", Data.lang:t("time_to_display"), 1, 10, 1)
    obs.obs_properties_add_int_slider(anim_props, "roll_delay", Data.lang:t("roll_delay"), 1, 200, 2)
    obs.obs_properties_add_int_slider(anim_props, "deceleration", Data.lang:t("deceleration"), 0, 1000, 50)
    obs.obs_properties_add_group(
        props, "animation_group", Data.lang:t("animation_group"),
        obs.OBS_GROUP_NORMAL, anim_props
    )

    local sound_props = obs.obs_properties_create()
    obs.obs_properties_add_bool(sound_props, "play_sound", Data.lang:t("play_sound"))
    obs.obs_properties_add_text(sound_props, "sound_path", Data.lang:t("sound_path"), obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_group(
        props, "sound_group", Data.lang:t("sound_group"),
        obs.OBS_GROUP_NORMAL, sound_props
    )

    obs.obs_properties_add_button(props, "button", Data.lang:t("get_random"), on_get_random_click)
    obs.obs_properties_add_button(props, "button2", Data.lang:t("reset"), on_clear_click)

    return props
end
