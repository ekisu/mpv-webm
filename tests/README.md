# Testing mpv-webm

Run from the repository root:

```sh
nix-shell tests/default.nix --run "make && python -m tests.run_tests"
```

`make` builds `build/webm.lua` normally. Tests load that file into a real mpv
process; they do not compile source fragments, inject alternate Lua chunks,
or replace mpv properties with mocks. The test environment includes mpv,
FFmpeg/ffprobe, Xvfb and xdotool, along with the normal build tools.

## Integration helpers

`BaseTestCase` creates an isolated temporary working/output directory, loads
the built script, drains verbose logs, and tears down the IPC reader and
player/encoder process group even when setup or a test fails. Failures include
mpv logs. `getLog()` exposes captured output for command-level assertions.

- `createVideo(...)`: generate a small FFV1 fixture with FFmpeg.
- `openTestVideoFile(path)`: load and pause media.
- `setProperty(name, value)`, `getProperty(name)`: access real mpv properties.
- `updateScriptOptions(options)`: configure the loaded script and await acknowledgement.
- `encodeClip(start, end, region=None, options=None)`: select exact timestamps
  and optional crop bounds, invoke the normal MainPage encoder, await a fresh
  completion event, and assert success.
- `getState()`: inspect the controller's selected range/region and actual
  mouse/OSD coordinates through the testing script-message interface.
- `decodeVideo(path)`, `probeVideo(path)`: inspect produced media.

For example:

```python
self.openTestVideoFile(self.createVideo())
self.encodeClip(1, 2, options={"output_format": "avc", "output_template": "clip"})
self.assertGreater((self.tempdir / "clip.mp4").stat().st_size, 0)
```

Use `event_cursor` / `waitForEvent(..., after=cursor)` around actions that must
produce a new event. Helpers already do this. Wait for observable state with
`waitUntil` rather than sleeping for a guessed duration.

## GUI tests

`GuiTestCase` starts its own Xvfb server, using `-displayfd` to allocate a free
display, and renders mpv with the X11 software output. No desktop session or
hardware GPU is needed. Each test gets its own server; startup errors fail
rather than silently skipping GUI coverage.

`moveMouse(x, y)` sends real window-relative X pointer motion and waits until
mpv observes the coordinates. `guiKey(key, event=...)` sends real X key events.
Crop regressions must use these UI controls and inspect the selected region;
passing `region=` to `encodeClip` alone does not test mouse-coordinate mapping.

Run just the GUI smoke test:

```sh
nix-shell tests/default.nix --run "make && python -m unittest tests.testcases.test_gui -v"
```

IPC transport unit tests use real sockets to exercise split/coalesced JSON,
UTF-8 framing, repeated events, concurrent requests, timeouts and disconnects.
These transport tests do not stand in for mpv integration coverage.
