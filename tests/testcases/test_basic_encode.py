from .base_test_case import BaseTestCase


class TestBasicEncode(BaseTestCase):
    def test_basic_encode(self):
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options={"output_template": "basic"})
        self.assertGreater((self.tempdir / "basic.webm").stat().st_size, 0)

    def test_repeated_encodes_use_new_range_and_events(self):
        self.openTestVideoFile(self.createVideo())
        options = {"output_format": "avc", "twopass": False,
                   "target_filesize": 100, "output_template": "short"}
        first = self.encodeClip(0, 0.5, options=options)
        self.assertEqual(self.getState()["endTime"], 0.5)
        second = self.encodeClip(1, 2, options={"output_template": "long"})
        self.assertIsNot(first, second)
        self.assertEqual(self.getState()["startTime"], 1)
        self.assertEqual(self.getState()["endTime"], 2)
        short = self.decodeVideo(self.tempdir / "short.mp4")
        long = self.decodeVideo(self.tempdir / "long.mp4")
        frame_size = 320 * 180 * 3
        self.assertEqual(len(short) % frame_size, 0)
        self.assertEqual(len(long) % frame_size, 0)
        self.assertGreater(len(short), 0)
        self.assertGreater(len(long), len(short))
