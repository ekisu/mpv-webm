from .base_test_case import BaseTestCase


class TestTwopassConstantQuality(BaseTestCase):
    def checkEncode(self, output_format, expect_twopass, target_filesize=0):
        self.openTestVideoFile(self.createVideo(size="64x64"))
        extra = "--no-config --scripts-clr"
        if output_format == "av1":
            codecs = self.runTool("mpv", "--no-config", "--scripts-clr", "--ovc=help")
            if b"libaom-av1" not in codecs:
                self.skipTest("This mpv build does not include the optional libaom-av1 encoder")
            extra += " --ovcopts-add=cpu-used=8"
        self.encodeClip(0, 1, options={
            "output_format": output_format, "target_filesize": target_filesize,
            "twopass": True, "threads": 2, "crf": 20,
            "output_template": "twopass-check", "additional_flags": extra,
        })
        extension = "webm" if output_format == "webm-vp8" else "mp4"
        output = self.tempdir / ("twopass-check." + extension)
        self.assertGreater(output.stat().st_size, 0)
        self.assertGreater(len(self.decodeVideo(output)), 0)
        self.waitUntil(lambda: "Command line:" in self.getLog(), "encoder command log")
        log = self.getLog()
        self.assertEqual("First-pass command line:" in log, expect_twopass, log)
        self.assertEqual("--ovcopts-add=flags=+pass2" in log, expect_twopass, log)

    def test_avc_twopass_constant_quality(self):
        self.checkEncode("avc", False)

    def test_hevc_twopass_constant_quality(self):
        self.checkEncode("hevc", False)

    def test_vp8_keeps_constant_quality_twopass(self):
        self.checkEncode("webm-vp8", True)

    def test_av1_keeps_constant_quality_twopass(self):
        self.checkEncode("av1", True)

    def test_avc_keeps_bitrate_targeted_twopass(self):
        self.checkEncode("avc", True, target_filesize=250)
