# mpv-webm
Simple WebM maker for [mpv][mpv], with no external dependencies.

![sample](/img/sample.jpg)

## Installation
Place [this][build] in your mpv `scripts` folder. The `scripts` folder can be found (or created, if it does not already exist) in the following paths:
- Linux/macOS: `~/.config/mpv/scripts`, where `~` is your user's home folder;
- Windows: mpv will try to load scripts from `%APPDATA%\mpv\scripts`, followed by `<mpv binary folder>\portable_config\scripts` and `<mpv binary folder>\mpv\scripts`; where `%APPDATA%` is a Windows-specific directory (typing `%APPDATA%` on Windows + R should take you to that folder), and `<mpv binary folder>` is the folder that contains the `mpv.exe` binary.

Additional details about the folder structure can be found in the [mpv's manual][file locations].

By default, the script is activated by the W (shift+w) key.

## Usage
Follow the on-screen instructions. Encoded WebM files will have audio/subs based on the current playback options (i.e. will be muted if no audio, won't have hardcoded subs if subs aren't visible).

## Configuration
You can configure the script's defaults by either changing the `options` at the beginning of the script, or placing a `webm.conf` inside the `script-opts` directory. A sample `webm.conf` file with the default options can be found [here][conf]. Note that you don't need to specify all options, only the ones you wish to override.

## Building (development)
Building requires [`moonc`, the MoonScript compiler][moonscript], added to the PATH, and a GNUMake compatible make. Run `make` on the root directory. The output files will be placed under the `build` directory.

[build]: https://github.com/ekisu/mpv-webm/releases/download/latest/webm.lua
[file locations]: https://mpv.io/manual/master/#files
[conf]: https://github.com/ekisu/mpv-webm/releases/download/latest/webm.conf
[mpv]: http://mpv.io
[moonscript]: http://moonscript.org
