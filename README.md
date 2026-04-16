# OBS Random text

A plugin to display a random string from a list. Once shown, the string is removed from the list.

https://user-images.githubusercontent.com/6481750/128868175-1e54b3f8-58a7-4882-934e-718983e1f2bd.mp4

## Features

- Simple animation with customization
- Optional sound effect on result
- Hotkeys support (you can set hotkeys in OBS preferences)
- Language selection
- Saving settings

## Installation

Requires OBS 28+. Lua is bundled — nothing else to install.

1. Download the repo, unpack it. Keep `random-text.lua` next to the `random-text/` folder.
2. Put the folder anywhere readable — OBS remembers the full path you pick.
3. OBS → **Tools → Scripts → `+`** → pick `random-text.lua`.
4. Set a hotkey in **Settings → Hotkeys → "Select random string"**.

Scripts have no fixed location (unlike binary plugins in the [OBS plugins guide](https://obsproject.com/kb/plugins-guide)). Suggested folders to keep things tidy:

| Platform       |Path|
|----------------|-|
| Windows        |`%APPDATA%\obs-studio\scripts\`|
| macOS          |`~/Library/Application Support/obs-studio/scripts/`|
| macOS (in-app) |`/Applications/OBS.app/Contents/Resources/scripts/`|
| Linux          |`~/.config/obs-studio/scripts/`|

## F.A.Q.

### Why are there so few settings and animations?

The plugin was made specially for a friend's stream to do a specific tasks. Feel free to add something of your own.
