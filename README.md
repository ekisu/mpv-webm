# mpv-webm
Simple WebM maker for [mpv][mpv], with no external dependencies.

![sample](/img/sample.jpg)

## Installation
Place [this][build] in your mpv `scripts` folder. The `scripts` folder can be found (or created, if it does not already exist) in the following paths:
- Linux/macOS: `~/.config/mpv/scripts`, where `~` is your user's home folder;
- Windows: mpv will try to load scripts from `%APPDATA%\mpv\scripts`, followed by `<mpv binary folder>\portable_config\scripts` and `<mpv binary folder>\mpv\scripts`; where `%APPDATA%` is a Windows-specific directory (typing `%APPDATA%` on Windows + R should take you to that folder), and `<mpv binary folder>` is the folder that contains the `mpv.exe` binary.

Additional details about the folder structure can be found in the [mpv's manual][file locations].

### Encoder executable

Encoding starts a separate `mpv` process. The `mpv` executable must be available on the `PATH` inherited by the player, including when the player is opened from a desktop shortcut or file manager.

- **Windows:** follow the [Windows encoder setup guide](docs/windows-encoder-setup.md) for step-by-step instructions to add mpv to `Path`, verify it, and troubleshoot desktop launches.
- **Linux/macOS:** run `command -v mpv` to check your shell's `PATH`. If encoding reports `mpv: command not found` when launched from the desktop, ensure that launch environment also includes the executable's directory. Homebrew commonly installs it in `/opt/homebrew/bin` on Apple Silicon and `/usr/local/bin` on Intel Macs.

If encoding instead reports a missing codec, check `mpv --ovc=help` for video encoders or `mpv --oac=help` for audio encoders. These lists come from the FFmpeg libraries used by **mpv**; installing a separate `ffmpeg` executable does not necessarily add codecs to mpv. On macOS, the Homebrew formula (`brew install mpv`) is one source of an encoder-enabled build.

By default, the script is activated by the W (shift+w) key.

## Usage
Follow the on-screen instructions. Encoded WebM files will have audio/subs based on the current playback options (i.e. will be muted if no audio, won't have hardcoded subs if subs aren't visible).

### Uploading

Press `u` (encode & upload) on the WebM maker page to encode a clip and upload it in one step. The destination is set in the options (`o`) and stored in `webm.conf`:

- `upload_host` — `catbox` (permanent) or `litterbox` (temporary).
- `litterbox_time` — expiry for litterbox uploads: `1h`, `12h`, `24h` or `72h`.
- `catbox_userhash` — optional Catbox account hash; account uploads are permanent and manageable.
- `upload_curl_path` — the `curl` executable used for the multipart upload.
- `open_after_upload` — open the link in the browser as soon as it is ready.

Uploads use `curl`; when it is not on `PATH`, the `u` line is hidden. The resulting URL is copied to the clipboard (mpv's `clipboard/text` when available, otherwise `wl-copy`, `xclip` or `pbcopy`). Only the Catbox services are supported: Streamable requires an account for uploads, so it is not offered.

## Configuration
You can configure the script's defaults by either changing the `options` at the beginning of the script, or placing a `webm.conf` inside the `script-opts` directory. A sample `webm.conf` file with the default options can be found [here][conf]. Note that you don't need to specify all options, only the ones you wish to override.

## Building (development)
Building requires [`moonc`, the MoonScript compiler][moonscript], added to the PATH, and a GNUMake compatible make. Run `make` on the root directory. The output files will be placed under the `build` directory.

[build]: https://github.com/ekisu/mpv-webm/releases/download/latest/webm.lua
[file locations]: https://mpv.io/manual/master/#files
[conf]: https://github.com/ekisu/mpv-webm/releases/download/latest/webm.conf
[mpv]: http://mpv.io
[moonscript]: http://moonscript.org
