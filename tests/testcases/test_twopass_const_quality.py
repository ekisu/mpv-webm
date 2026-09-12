import tempfile
import threading
from pathlib import Path
import time
from tests.mpv_ipc import MpvScriptMessageEvent
from .base_test_case import BaseTestCase


class TestTwopassConstantQuality(BaseTestCase):
    def setUp(self):
        super().setUp()
        # Capture verbose command lines while draining the otherwise unread pipe.
        self.log = []
        self.log_reader = threading.Thread(target=self.read_log)
        self.log_reader.start()

    def read_log(self):
        for line in self.mpv_process.stdout:
            self.log.append(line.decode(errors="replace"))

    def tearDown(self):
        super().tearDown()
        self.mpv_process.wait(timeout=10)
        self.log_reader.join(timeout=10)
        self.mpv_process.stdout.close()

    def check_encode(self, output_format, expect_twopass, target_filesize=0):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-twopass-") as tmpdir:
            self.openTestVideoFile(Path("tests/videos/big_buck_bunny_10s.mp4"))
            extra = "--no-config --scripts-clr"
            if output_format == "av1":
                extra += " --ovcopts-add=cpu-used=8"
            self.updateScriptOptions({
                "output_format": output_format,
                "target_filesize": target_filesize,
                "twopass": True,
                "threads": 2,
                "scale_height": 144,
                "fps": 10,
                "crf": 20,
                "output_directory": tmpdir,
                "output_template": "twopass-check",
                "display_progress": False,
                "additional_flags": extra,
            })
            self.sendKeyPress("Shift+W")
            self.waitForEvent("webm-show-main-page")
            time.sleep(1)
            self.sendCommandToMpv({"command": ["seek", 0, "absolute"]})
            time.sleep(0.5)
            self.sendKeyPress("1")
            self.sendCommandToMpv({"command": ["seek", 2, "absolute"]})
            time.sleep(0.5)
            self.sendKeyPress("2")
            time.sleep(0.5)
            self.sendKeyPress("e")
            event = self.waitForEvent("webm-encode-finished", timeout=60)
            self.assertIsInstance(event, MpvScriptMessageEvent)
            self.assertEqual(["webm-encode-finished", "success"], event.args)
            extension = "webm" if output_format == "webm-vp8" else "mp4"
            output = Path(tmpdir) / ("twopass-check." + extension)
            self.assertTrue(output.is_file())
            self.assertGreater(output.stat().st_size, 0)
            # Stop the player and finish draining so all logged commands are visible.
            self.mpv_process.terminate()
            self.mpv_process.wait(timeout=10)
            self.log_reader.join(timeout=10)
            log = "".join(self.log)
            self.assertEqual("First-pass command line:" in log, expect_twopass, log[-4000:])
            self.assertEqual("--ovcopts-add=flags=+pass2" in log, expect_twopass, log[-4000:])

    def test_avc_twopass_constant_quality(self):
        self.check_encode("avc", False)

    def test_hevc_twopass_constant_quality(self):
        self.check_encode("hevc", False)

    def test_vp8_keeps_constant_quality_twopass(self):
        self.check_encode("webm-vp8", True)

    def test_av1_keeps_constant_quality_twopass(self):
        self.check_encode("av1", True)

    def test_avc_keeps_bitrate_targeted_twopass(self):
        self.check_encode("avc", True, target_filesize=250)
