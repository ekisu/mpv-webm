from .base_test_case import BaseTestCase


class TestStrictFilesize(BaseTestCase):
    def checkEncode(self, output_format):
        if output_format == "mp3":
            source = self.tempdir / "tone.wav"
            self.runTool("ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                         "sine=frequency=440:duration=2", str(source))
            target, end, expected, stream, extension = 32, 2, 128, "oac", "mp3"
        else:
            source = self.createVideo()
            target, end, expected, stream, extension = 100, 1, 800, "ovc", "mp4"
        self.openTestVideoFile(source)
        self.encodeClip(0, end, options={
            "output_format": output_format, "target_filesize": target,
            "strict_filesize_constraint": True, "twopass": False,
            "output_template": "strict",
        })
        output = self.tempdir / ("strict." + extension)
        self.assertGreater(output.stat().st_size, 100)
        self.assertTrue(self.probeVideo(output)["streams"])
        self.waitUntil(lambda: "Command line:" in self.getLog(), "encoder command log")
        command = next(line for line in self.getLog().splitlines() if "Command line:" in line)
        for option in ("b", "minrate", "maxrate"):
            self.assertIn(f"--{stream}opts-add={option}={expected}k", command)
        self.assertNotIn("nilk", command)

    def test_video_strict_bitrate(self):
        self.checkEncode("avc")

    def test_audio_only_strict_bitrate(self):
        self.checkEncode("mp3")
