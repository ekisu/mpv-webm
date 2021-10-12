from .base_test_case import BaseTestCase
from pathlib import Path

import time

class TestBasicEncode(BaseTestCase):
    def test_basic_encode(self):
        self.openTestVideoFile(Path('tests/videos/big_buck_bunny_10s.mp4'))

        self.sendKeyPress('Shift+W')
        self.waitForEvent('webm-show-main-page')

        # I'm not sure why this is needed...
        time.sleep(1)
        self.sendKeyPress('e')

        self.waitForEvent('webm-encode-success', timeout=60)

        # TODO Test if file exists? I guess