import hashlib

from .base_test_case import BaseTestCase


def _avc_options(template):
    return {
        "output_format": "avc",
        "twopass": False,
        "target_filesize": 100,
        "scale_height": -1,
        "output_template": template,
    }


class TestOutputTemplateSequence(BaseTestCase):
    def test_sequential_padded_counter_preserves_existing(self):
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options=_avc_options("clip_%04n"))
        first = self.tempdir / "clip_0001.mp4"
        self.assertTrue(first.is_file(), self.getLog())
        self.assertGreater(first.stat().st_size, 0)
        first_bytes = first.read_bytes()
        first_digest = hashlib.sha256(first_bytes).hexdigest()
        first_size = len(first_bytes)
        # Nonempty and decodable through real FFmpeg.
        frame_size = 320 * 180 * 3
        decoded = self.decodeVideo(first)
        self.assertGreater(len(decoded), 0)
        self.assertEqual(len(decoded) % frame_size, 0)

        self.encodeClip(0, 1, options=_avc_options("clip_%04n"))
        second = self.tempdir / "clip_0002.mp4"
        self.assertTrue(second.is_file(), self.getLog())
        self.assertGreater(second.stat().st_size, 0)
        decoded_second = self.decodeVideo(second)
        self.assertGreater(len(decoded_second), 0)
        self.assertEqual(len(decoded_second) % frame_size, 0)
        # First output is preserved byte-for-byte; no overwrite or truncation.
        self.assertEqual(first.stat().st_size, first_size)
        self.assertEqual(hashlib.sha256(first.read_bytes()).hexdigest(), first_digest)
        # Template was numbered, not left as a literal %04n file.
        self.assertFalse((self.tempdir / "clip_%04n.mp4").exists())

    def test_preexisting_collisions_fill_gaps(self):
        first_dummy = self.tempdir / "clip_0001.mp4"
        first_dummy.write_bytes(b"x" * 16)
        gap_dummy = self.tempdir / "clip_0003.mp4"
        gap_dummy.write_bytes(b"y" * 16)
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options=_avc_options("clip_%04n"))
        gap = self.tempdir / "clip_0002.mp4"
        self.assertTrue(gap.is_file(), self.getLog())
        self.assertGreater(gap.stat().st_size, 0)
        decoded = self.decodeVideo(gap)
        self.assertGreater(len(decoded), 0)
        # Preexisting files keep their exact bytes; gap number is reused.
        self.assertEqual(first_dummy.read_bytes(), b"x" * 16)
        self.assertEqual(gap_dummy.read_bytes(), b"y" * 16)
        self.assertFalse((self.tempdir / "clip_%04n.mp4").exists())

    def test_repeated_differently_padded_counters_share_sequence(self):
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options=_avc_options("multi_%n_%04n"))
        first = self.tempdir / "multi_1_0001.mp4"
        self.assertTrue(first.is_file(), self.getLog())
        self.assertGreater(first.stat().st_size, 0)
        first_bytes = first.read_bytes()
        self.assertGreater(len(self.decodeVideo(first)), 0)
        self.encodeClip(0, 1, options=_avc_options("multi_%n_%04n"))
        second = self.tempdir / "multi_2_0002.mp4"
        self.assertTrue(second.is_file(), self.getLog())
        self.assertGreater(second.stat().st_size, 0)
        self.assertGreater(len(self.decodeVideo(second)), 0)
        # Both counters advance together; the first file is preserved.
        self.assertEqual(first.read_bytes(), first_bytes)
        self.assertFalse((self.tempdir / "multi_%n_%04n.mp4").exists())

    def test_counter_like_source_filename_stays_literal(self):
        media = self.createVideo(name="pct_%04n_%1b_src.mkv")
        self.openTestVideoFile(media)
        self.encodeClip(0, 1, options=_avc_options("%F_%04n"))
        expected = self.tempdir / "pct_%04n_%1b_src_0001.mp4"
        self.assertTrue(expected.is_file(), self.getLog())
        self.assertGreater(expected.stat().st_size, 0)
        self.assertGreater(len(self.decodeVideo(expected)), 0)
        # Counter-like text from the media filename is not expanded as a
        # second template counter, and % captures stay literal.
        self.assertFalse((self.tempdir / "pct_%04n_%1b_src_%04n.mp4").exists())
