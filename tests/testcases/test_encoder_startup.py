import os
import shutil
import tempfile

from .base_test_case import BaseTestCase, ROOT


class TestMissingEncoder(BaseTestCase):
    def setUp(self):
        # Start a real player by absolute path, but make its child mpv lookup
        # fail. This reproduces a desktop launch with an incomplete PATH.
        self.mpv_executable = shutil.which("mpv")
        self.assertIsNotNone(self.mpv_executable)
        empty_path = tempfile.TemporaryDirectory(prefix="mpv-empty-path-")
        self.addCleanup(empty_path.cleanup)
        self.mpv_env = {**os.environ, "PATH": empty_path.name}
        super().setUp()

    def test_missing_encoder_reports_actionable_error_in_all_launch_modes(self):
        self.openTestVideoFile(ROOT / "tests/videos/big_buck_bunny_10s.mp4")
        self.setRange(0, 1)
        for mode in ({"display_progress": False, "run_detached": False, "twopass": False},
                     {"display_progress": True, "run_detached": False, "twopass": False},
                     {"display_progress": False, "run_detached": True, "twopass": False},
                     {"display_progress": False, "run_detached": False, "twopass": True}):
            with self.subTest(mode=mode):
                self.updateScriptOptions({**mode, "output_template": "missing"})
                event = self.scriptMessage("mpv-webm-encode", event="webm-encode-finished")
                self.assertEqual(event.args[:2], ["webm-encode-finished", "fail"])
                self.assertIn("Cannot start the mpv encoder", event.args[2])
                self.assertIn("PATH", event.args[2])
                self.assertIn("restart the player", event.args[2])
                self.waitUntil(lambda: event.args[2] in self.getLog(), "actionable encoder error log")
                self.assertFalse((self.tempdir / "missing.webm").exists())
