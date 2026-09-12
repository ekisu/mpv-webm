import unittest

from .base_test_case import BaseTestCase


class TestFormats(BaseTestCase):
    def _test_with_format(self, output_format, extension):
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options={"output_format": output_format,
                                      "output_template": "format"})
        self.assertGreater((self.tempdir / ("format." + extension)).stat().st_size, 0)

    def test_webm_vp9(self):
        self._test_with_format("webm-vp9", "webm")

    def test_avc(self):
        self._test_with_format("avc", "mp4")

    @unittest.skip("Our video fixture has no audio track.")
    def test_mp3(self):
        self._test_with_format("mp3", "mp3")

    def test_gif(self):
        self._test_with_format("gif", "gif")
