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
