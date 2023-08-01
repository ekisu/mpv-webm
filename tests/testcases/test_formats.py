import abc
from pathlib import Path
import time
import unittest

from tests.mpv_ipc import MpvScriptMessageEvent
from .base_test_case import BaseTestCase

class TestFormats(BaseTestCase):
    def _test_with_format(self, format):
        self.openTestVideoFile(Path('tests/videos/big_buck_bunny_10s.mp4'))

        self.updateScriptOptions({
            'output_format': format,
        })

        self.sendKeyPress('Shift+W')
        self.waitForEvent('webm-show-main-page')

        # I'm not sure why this is needed...
        time.sleep(1)
        self.sendKeyPress('e')

        finished_event = self.waitForEvent('webm-encode-finished', timeout=240)
        self.assertIsInstance(finished_event, MpvScriptMessageEvent)
        self.assertEqual(['webm-encode-finished', 'success'], finished_event.args)

    def test_webm_vp9(self):
        self._test_with_format('webm-vp9')
    
    def test_avc(self):
        self._test_with_format('avc')
    
    @unittest.skip('Our video file has no audio track yet.')
    def test_mp3(self):
        self._test_with_format('mp3')
    
    def test_gif(self):
        self._test_with_format('gif')

    # TODO Test raw (probably too big, would require using a smaller section)
    # and avc-nvenc (yeah, good luck using that on GitHub Actions)