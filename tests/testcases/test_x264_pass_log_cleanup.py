from .base_test_case import BaseTestCase


class TestX264PassLogCleanup(BaseTestCase):
    def test_bitrate_twopass_removes_x264_stats(self):
        self.openTestVideoFile(self.createVideo(size="64x64"))
        # Keep the output directory distinct from mpv's working directory:
        # libx264 writes its stats files into the encoder's current directory,
        # which is what the bug left behind.
        output_dir = self.tempdir / "out"
        output_dir.mkdir()
        self.encodeClip(0, 1, options={
            "output_format": "avc", "target_filesize": 250,
            "twopass": True, "threads": 2, "crf": 20,
            "output_template": "x264-twopass",
            "output_directory": str(output_dir),
        })
        output = output_dir / "x264-twopass.mp4"
        self.assertGreater(output.stat().st_size, 0)
        self.assertGreater(len(self.decodeVideo(output)), 0)
        # The stats files only exist because a real second pass looked them up;
        # make sure the regression test cannot pass vacuously.
        self.waitUntil(lambda: "--ovcopts-add=flags=+pass2" in self.getLog(),
                       "second pass command")
        self.assertIn("First-pass command line:", self.getLog())
        for name in ("x264_2pass.log", "x264_2pass.log.mbtree"):
            self.assertFalse((self.tempdir / name).exists(),
                             f"{name} was left behind after encoding")
