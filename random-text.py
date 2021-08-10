import obspython as obs
from pathlib import Path
from random import shuffle, randrange
from time import sleep
import json

SETTINGS_FILENAME = 'random-text.settings.json'
PROJECT_DIR = 'random-text'
AVAILABLE_LANGUAGES = ['en', 'ru']

# ------------------------------------------------------------

class Lang:
    def __init__(self, code):
        print(code)
        lang_file = Path(script_path() + '/' + PROJECT_DIR + '/lang/' + code + '.json')
        if not lang_file.is_file():
            raise Exception('Lang file not found')

        self.messages = json.loads(lang_file.read_text('utf-8'))

    def t(self, key):
        if key in self.messages:
            return self.messages[key]

        return key

# ------------------------------------------------------------

class Data:
    _props_ = None
    _settings_ = None

    lang_code = 'en'
    lang = Lang(lang_code)

    lines = []
    source_name = ""

    # animation
    with_animation = False
    deceleration = 50
    roll_delay = 42
    time_to_display = 2

    # sound
    play_sound = False
    sound_path = ""
    media_source = None # Null pointer
    output_index = 63 # Last index

# ------------------------------------------------------------

class Hotkey:
    def __init__(self, callback, obs_settings, _id, description):
        self.obs_data = obs_settings
        self.hotkey_id = obs.OBS_INVALID_HOTKEY_ID
        self.hotkey_saved_key = None
        self.callback = callback
        self._id = _id
        self.description = description

        self.load_hotkey()
        self.register_hotkey()
        self.save_hotkey()

    def register_hotkey(self):
        self.hotkey_id = obs.obs_hotkey_register_frontend(
            "htk_id" + str(self._id), self.description, self.callback
        )
        obs.obs_hotkey_load(self.hotkey_id, self.hotkey_saved_key)

    def load_hotkey(self):
        self.hotkey_saved_key = obs.obs_data_get_array(
            self.obs_data, "htk_id" + str(self._id)
        )
        obs.obs_data_array_release(self.hotkey_saved_key)

    def save_hotkey(self):
        self.hotkey_saved_key = obs.obs_hotkey_save(self.hotkey_id)
        obs.obs_data_set_array(
            self.obs_data, "htk_id" + str(self._id), self.hotkey_saved_key
        )
        obs.obs_data_array_release(self.hotkey_saved_key)


class HotkeyStore:
    htk_copy = None

# ------------------------------------------------------------

def update_text():
    source = obs.obs_get_source_by_name(Data.source_name)
    if source is not None:
        settings = obs.obs_data_create()

        # update source
        text = ''
        if len(Data.lines) > 0:
            text = Data.lines.pop()

        if Data.with_animation:
            animate_selection(settings, source, Data.lines + [text])

        obs.obs_data_set_string(settings, "text", text)
        obs.obs_source_update(source, settings)
        obs.obs_data_release(settings)
        obs.obs_source_release(source)

        if Data.play_sound:
            play_sound()
        
        # save changes
        obs.obs_data_set_string(Data._settings_, "text", "\n".join(Data.lines))
        save()

def animate_selection(settings, source, lines):
    time_limit = Data.time_to_display
    sleep_time = Data.roll_delay / 1000
    deceleration_default = Data.deceleration / 1000

    lines_count = len(lines)

    deceleration = 0
    speed_modification = 1
    while time_limit > 0:
        random_index = randrange(lines_count)
        obs.obs_data_set_string(settings, "text", lines[random_index])
        obs.obs_source_update(source, settings)

        current_sleep_time = sleep_time * (speed_modification + deceleration)
        time_limit = time_limit - current_sleep_time

        deceleration = deceleration + deceleration_default
        sleep(current_sleep_time)

def play_sound():
    if Data.media_source == None:
        Data.media_source = obs.obs_source_create_private(
            "ffmpeg_source", "Global Media Source", None
        )
    s = obs.obs_data_create()
    obs.obs_data_set_string(s, "local_file", Data.sound_path)
    obs.obs_source_update(Data.media_source, s)
    obs.obs_source_set_monitoring_type(
        Data.media_source, obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT
    )
    obs.obs_data_release(s)

    obs.obs_set_output_source(Data.output_index, Data.media_source)

def save():
    if not Data._settings_:
        return

    p = Path(__file__).absolute()
    file = p.parent / PROJECT_DIR / SETTINGS_FILENAME

    try:
        content = obs.obs_data_get_json(Data._settings_)
        with open(file, "w") as f:
            f.write(content)
    except Exception as e:
        print(e, "can't save settings")

def load():
    file = Path(script_path() + '/' + PROJECT_DIR + '/' + SETTINGS_FILENAME)
    if file.is_file():
        data = obs.obs_data_create_from_json(file.read_text('utf-8'))
        lang_code = obs.obs_data_get_string(data, "lang")
        if lang_code:
            Data.lang_code = lang_code
            Data.lang = Lang(lang_code)

def on_get_random_click(props, prop):
    update_text()

def on_get_random_hotkey_pressed(pressed):
    if pressed:
        update_text()

def on_clear_click(props, prop):
    Data.lines = []
    obs.obs_data_set_string(Data._settings_, "text", "\n".join(Data.lines))
    save()

# ------------------------------------------------------------

hotkey_get_random = HotkeyStore()
load()

# ------------------------------------------------------------


def script_load(settings):
    hotkey_get_random.htk_copy = Hotkey(on_get_random_hotkey_pressed, settings, "get_random_text", Data.lang.t('get_random'))

def script_save(settings):
    hotkey_get_random.htk_copy.save_hotkey()

def script_description():
    return Data.lang.t('description')

def script_update(settings):
    text = obs.obs_data_get_string(settings, "text")
    lines = text.splitlines()
    lines = list(filter(lambda x: x.strip() != '', lines))
    shuffle(lines)

    Data._settings_ = settings
    Data.lines = lines
    Data.source_name = obs.obs_data_get_string(settings, "source")

    # animation
    Data.with_animation = obs.obs_data_get_bool(settings, "with_animation")
    Data.deceleration = obs.obs_data_get_int(settings, "deceleration")
    Data.time_to_display = obs.obs_data_get_int(settings, "time_to_display")
    Data.roll_delay = obs.obs_data_get_int(settings, "roll_delay")

    # sound
    Data.play_sound = obs.obs_data_get_bool(settings, "play_sound")
    Data.sound_path = obs.obs_data_get_string(settings, "sound_path")

    # language
    Data.lang_code = obs.obs_data_get_string(settings, "lang")
    Data.lang = Lang(Data.lang_code)

    save()

def script_defaults(settings):
    obs.obs_data_set_default_string(settings, "text", "1. \n2. \n3. \n")

    # animation
    obs.obs_data_set_default_bool(settings, "with_animation", Data.with_animation)
    obs.obs_data_set_default_int(settings, "roll_delay", Data.roll_delay)
    obs.obs_data_set_default_int(settings, "time_to_display", Data.time_to_display)
    obs.obs_data_set_default_int(settings, "deceleration", Data.deceleration)

    # sound
    obs.obs_data_set_default_string(settings, "sound_path", script_path() + PROJECT_DIR + "/alert.mp3")

    # language
    obs.obs_data_set_default_string(settings, "lang", "en")

def script_properties():
    props = obs.obs_properties_create()
    Data._props_ = props

    # language
    l = obs.obs_properties_add_list(props, "lang", "Language", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    for lang in AVAILABLE_LANGUAGES:
        obs.obs_property_list_add_string(l, lang, lang)

    obs.obs_properties_add_text(props, "text", Data.lang.t('options'), obs.OBS_TEXT_MULTILINE)

    p = obs.obs_properties_add_list(props, "source", Data.lang.t('source'), obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    sources = obs.obs_enum_sources()
    if sources is not None:
        for source in sources:
            source_id = obs.obs_source_get_unversioned_id(source)
            if source_id == "text_gdiplus" or source_id == "text_ft2_source":
                name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(p, name, name)

        obs.source_list_release(sources)

    # animation
    obs.obs_properties_add_bool(props, "with_animation", Data.lang.t('with_animation'))
    obs.obs_properties_add_int_slider(props, "time_to_display", Data.lang.t('time_to_display'), 1, 10, 1)
    obs.obs_properties_add_int_slider(props, "roll_delay", Data.lang.t('roll_delay'), 1, 200, 2)
    obs.obs_properties_add_int_slider(props, "deceleration", Data.lang.t('deceleration'), 0, 1000, 50)

    # sound
    obs.obs_properties_add_bool(props, "play_sound", Data.lang.t('play_sound'))
    obs.obs_properties_add_text(props, "sound_path", Data.lang.t('sound_path'), obs.OBS_TEXT_DEFAULT)

    obs.obs_properties_add_button(props, "button", Data.lang.t('get_random'), on_get_random_click)
    obs.obs_properties_add_button(props, "button2", Data.lang.t('reset'), on_clear_click)

    return props