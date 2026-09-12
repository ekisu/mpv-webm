from .test_gui import GuiTestCase


class CropGuiTestCase(GuiTestCase):
    def selectRegion(self, first, second):
        self.guiKey("W", "webm-show-main-page")
        self.guiKey("c", "webm-show-crop-page")
        self.moveMouse(*first)
        first_event = self.guiKey("1", "webm-crop-point-a")
        self.moveMouse(*second)
        second_event = self.guiKey("2", "webm-crop-point-b")
        self.guiKey("Return", "webm-show-main-page")
        return (self.getState()["region"],
                tuple(map(int, first_event.args[1:])),
                tuple(map(int, second_event.args[1:])))

    def openSource(self):
        self.openTestVideoFile(self.createVideo(size="640x360"))
        self.waitForWindow()
        params = self.getProperty("video-out-params")
        self.assertEqual((params["w"], params["h"]), (640, 360))


class TestCropEdges(CropGuiTestCase):
    def test_full_frame_and_reverse_selection(self):
        self.openSource()
        for first, second in (((0, 0), (639, 359)), ((639, 359), (0, 0))):
            with self.subTest(first=first):
                region, a, b = self.selectRegion(first, second)
                self.assertEqual(region, {"x": 0, "y": 0, "w": 640, "h": 360})
                self.assertEqual(set((a, b)), {(0, 0), (640, 360)})
                # Leave the main page before reopening it for another selection.
                self.guiKey("Escape")
                self.waitUntil(lambda: not self.getState()["mainVisible"], "main page to close")

    def test_interior_selection_is_unchanged(self):
        self.openSource()
        region, a, b = self.selectRegion((100, 80), (500, 300))
        self.assertEqual((a, b), ((100, 80), (500, 300)))
        self.assertEqual(region, {"x": 100, "y": 80, "w": 400, "h": 220})
        self.encodeClip(0, 1, options={"output_format": "avc", "twopass": False,
                                      "output_template": "cropped", "target_filesize": 100})
        stream = self.probeVideo(self.tempdir / "cropped.mp4")["streams"][0]
        self.assertEqual((stream["width"], stream["height"]), (400, 220))


class TestDownscaledCropEdges(CropGuiTestCase):
    window_size = (320, 180)

    def test_last_window_pixel_includes_full_source(self):
        self.openSource()
        region, a, b = self.selectRegion((0, 0), (319, 179))
        self.assertEqual((a, b), ((0, 0), (640, 360)))
        self.assertEqual(region, {"x": 0, "y": 0, "w": 640, "h": 360})


class TestLetterboxedCropEdges(CropGuiTestCase):
    window_size = (640, 480)

    def test_last_video_pixel_includes_full_source(self):
        self.openSource()
        # 640x360 video is centered in the actual 640x480 X window.
        region, a, b = self.selectRegion((0, 60), (639, 419))
        self.assertEqual((a, b), ((0, 0), (640, 360)))
        self.assertEqual(region, {"x": 0, "y": 0, "w": 640, "h": 360})
