from .base_test_case import BaseTestCase


class TestVideoFilters(BaseTestCase):
    def test_disabled_current_filters_ignore_color_adjustments(self):
        source = self.createVideo(color="red")
        self.openTestVideoFile(source)
        base_options = {
            "output_format": "avc",
            "twopass": False,
            "target_filesize": 100,
        }

        self.setProperty("brightness", 0)
        self.setProperty("contrast", 0)
        self.setProperty("saturation", 0)
        self.encodeClip(0, 1, options={
            **base_options,
            "apply_current_filters": True,
            "output_template": "neutral",
        })
        neutral = self.decodeVideo(self.tempdir / "neutral.mp4")

        self.setProperty("brightness", 50)
        self.setProperty("contrast", 50)
        self.setProperty("saturation", -100)
        self.encodeClip(0, 1, options={
            **base_options,
            "apply_current_filters": False,
            "output_template": "disabled",
        })
        disabled = self.decodeVideo(self.tempdir / "disabled.mp4")

        self.encodeClip(0, 1, options={
            **base_options,
            "apply_current_filters": True,
            "output_template": "enabled",
        })
        enabled = self.decodeVideo(self.tempdir / "enabled.mp4")

        self.assertGreater(len(neutral), 0)
        self.assertEqual(disabled, neutral)
        self.assertNotEqual(enabled, neutral)

    def test_gif_applies_lavfi_crop_current_filter(self):
        # mpv reports libavfilter bridge filters such as "lavfi-crop" with
        # positional parameters named @0, @1, ...; the GIF format rewrites the
        # command line into a raw libavfilter graph, where those names are
        # invalid. Regression test for GIF encoding failing with them.
        self.openTestVideoFile(self.createVideo())
        self.sendCommandToMpv({"command": ["vf", "add", "lavfi-crop=320:100:0:40"]})
        self.encodeClip(0, 1, options={
            "output_format": "gif",
            "apply_current_filters": True,
            "output_template": "crop",
            "scale_height": 90,
            "fps": 10,
        })
        streams = self.probeVideo(self.tempdir / "crop.gif")["streams"]
        self.assertEqual((streams[0]["width"], streams[0]["height"]), (288, 90))

    def test_gif_applies_lavfi_graph_current_filter(self):
        self.openTestVideoFile(self.createVideo())
        self.sendCommandToMpv({"command": ["vf", "add", "lavfi=[crop=320:100:0:40]"]})
        self.encodeClip(0, 1, options={
            "output_format": "gif",
            "apply_current_filters": True,
            "output_template": "graph",
            "scale_height": 90,
            "fps": 10,
        })
        streams = self.probeVideo(self.tempdir / "graph.gif")["streams"]
        self.assertEqual((streams[0]["width"], streams[0]["height"]), (288, 90))

    def test_gif_applies_lavfi_eq_current_filter(self):
        self.openTestVideoFile(self.createVideo())
        self.sendCommandToMpv({"command": ["vf", "add", "lavfi-eq=contrast=1.5:saturation=1.5"]})
        self.encodeClip(0, 1, options={
            "output_format": "gif",
            "apply_current_filters": True,
            "output_template": "eq",
            "scale_height": 90,
            "fps": 10,
        })
        self.assertGreater((self.tempdir / "eq.gif").stat().st_size, 0)

    def test_avc_applies_lavfi_crop_current_filter(self):
        self.openTestVideoFile(self.createVideo())
        self.sendCommandToMpv({"command": ["vf", "add", "lavfi-crop=320:100:0:40"]})
        self.encodeClip(0, 1, options={
            "output_format": "avc",
            "apply_current_filters": True,
            "twopass": False,
            "target_filesize": 100,
            "output_template": "crop-avc",
        })
        streams = self.probeVideo(self.tempdir / "crop-avc.mp4")["streams"]
        self.assertEqual((streams[0]["width"], streams[0]["height"]), (320, 100))
