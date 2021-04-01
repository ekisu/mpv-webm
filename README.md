# mpv-webm
Simple WebM maker for [mpv][mpv], with no external dependencies.

![sample](/img/sample.jpg)

## Installation
Place [this][build] in your mpv `scripts` folder. By default, the script is activated by the W (shift+w) key.

## Usage
Follow the on-screen instructions. Encoded WebM files will have audio/subs based on the current playback options (i.e. will be muted if no audio, won't have hardcoded subs if subs aren't visible).

## Building (development)
Building requires [`moonc`, the MoonScript compiler][moonscript], added to the PATH, and a GNUMake compatible make. Run `make` on the root directory. The output files will be placed under the `build` directory.

[build]: https://github.com/ekisu/mpv-webm/releases/download/latest/webm.lua
[mpv]: http://mpv.io
[moonscript]: http://moonscript.org
