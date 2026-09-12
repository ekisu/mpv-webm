from tests.xvfb import XvfbDisplay
from .base_test_case import BaseTestCase


class GuiTestCase(BaseTestCase):
    window_size = (640, 360)

    def setUp(self):
        self.display = XvfbDisplay()
        self.display.__enter__()
        self.addCleanup(self.display.close)
        self.mpv_env = self.display.env
        width, height = self.window_size
        self.mpv_args = ("--vo=x11", "--force-window=immediate", "--border=no",
                         "--osc=no", "--keepaspect-window=no",
                         f"--geometry={width}x{height}+0+0")
        super().setUp()
        self.window = self.display.wait_for_window(self.mpv_process.pid)

    def waitForWindow(self):
        width, height = self.window_size
        self.waitUntil(lambda: self.getState()["osd"] == {"w": width, "h": height},
                       "mpv OSD to match the X window")
        geometry = self.display.geometry(self.window)
        self.assertEqual((geometry["width"], geometry["height"]), self.window_size)

    def moveMouse(self, x, y):
        self.display.move_mouse(self.window, x, y)
        self.waitUntil(lambda: self.getState()["mouse"] == {"x": x, "y": y},
                       f"mpv to receive mouse motion to ({x}, {y})")

    def guiKey(self, key, event=None):
        # Lua installs bindings at the next event-loop idle point, after the
        # page's show event. Wait for the core to register them before X input.
        mpv_key = {"Escape": "ESC", "Return": "ENTER"}.get(key, key)
        self.waitUntil(lambda: any(
            binding.get("key") == mpv_key and binding.get("owner") == "webm"
            for binding in self.getProperty("input-bindings")),
            f"webm key binding {mpv_key} to be registered")
        cursor = self.mpv_ipc.event_cursor
        self.display.key(self.window, key)
        if event is not None:
            return self.waitForEvent(event, after=cursor)


class TestGuiHarness(GuiTestCase):
    def test_real_mouse_and_crop_key_events(self):
        self.openTestVideoFile(self.createVideo(size="640x360"))
        self.waitForWindow()
        self.moveMouse(123, 87)
        self.guiKey("W", "webm-show-main-page")
        self.assertTrue(self.getState()["mainVisible"])
        self.guiKey("c", "webm-show-crop-page")
        self.assertFalse(self.getState()["mainVisible"])
        self.guiKey("Escape", "webm-show-main-page")
        self.assertTrue(self.getState()["mainVisible"])
