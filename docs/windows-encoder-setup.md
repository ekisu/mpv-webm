# Windows encoder setup

mpv-webm starts a second `mpv.exe` to encode your clip. Windows must be able to
find it through the `Path` environment variable, even when you open the player
by double-clicking a video.

## 1. Locate mpv

If needed, get a Windows build from the [mpv installation page](https://mpv.io/installation/).
Extract the archive into a permanent folder, for example `C:\Tools\mpv`.
Check that `mpv.exe` is directly inside that folder. Use your actual folder in
the steps below; do not add the archive or the executable filename to `Path`.

## 2. Add that folder to your user Path

1. Open **Start**, search for **Edit environment variables for your account**,
   and open that settings dialog.
2. Under **User variables for your account**, select **Path**, then **Edit**.
3. Click **New** and enter the folder containing `mpv.exe`, for example
   `C:\Tools\mpv`. Keep the existing entries. Do not put quotes around the folder.
4. If your account has no `Path` variable yet, click **New** in the User variables
   section, use `Path` as the name and the mpv folder as the value.
5. Click **OK** in each dialog to save the change.

## 3. Verify and restart the player

Close existing Command Prompt and mpv windows. Open a **new Command Prompt**
from Start and run:

```bat
where mpv
mpv --version
```

`where mpv` should print the path to your `mpv.exe`, and `mpv --version` should
print version information. If Windows cannot find it, check that the folder
from step 2 really contains `mpv.exe` and that the change was saved.

Open mpv again and try encoding. If a terminal launch works but opening a video
from Explorer still fails, sign out of Windows and sign back in so Explorer
and other launchers inherit the updated environment. Restart third-party
launchers too. File associations alone do not put mpv on `Path`.

If `where mpv` lists multiple copies, Windows normally selects the first one.
Check that it is the build you intended to use.

## 4. If mpv starts but an encoder is missing

Run:

```bat
mpv --ovc=help
mpv --oac=help
```

These list the video and audio encoders in your mpv build. Select a supported
format or install an mpv build with the required codec. Installing a separate
FFmpeg executable does not change the codecs compiled into mpv.

The message **Cannot start the mpv encoder** points to an executable startup
problem; the message **mpv encoder failed its startup check** means mpv was
launched but returned an error. Run `mpv --version` and inspect the player logs
for the underlying diagnostic.
