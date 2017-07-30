# mpv-webm
Simple WebM maker for [mpv][mpv], with no external dependencies.

![sample](/img/sample.jpg)

## Installation
Place the [compiled `webm.lua`][build] inside the `build` directory file to your mpv scripts folder. By default, it's bound to the W (shift+w) key.

## Building
Building requires [`moonc`, the MoonScript compiler][moonscript], added to the PATH, and a GNUMake compatible make. Run `make` on the root directory. The output files will be placed under the `build` directory.

[build]: https://raw.githubusercontent.com/ElegantMonkey/mpv-webm/master/build/webm.lua
[mpv]: http://mpv.io
[moonscript]: http://moonscript.org
