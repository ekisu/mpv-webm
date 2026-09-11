"""Verify strict bitrate flags by completing real video and audio-only encodes."""
import array
import json
import math
import subprocess
import sys
import tempfile
import time
import unittest
import wave
from pathlib import Path

from tests.mpv_ipc import MpvIPC


ROOT = Path(__file__).resolve().parents[2]


class TestStrictFilesize(unittest.TestCase):
    def encode(self, output_format):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-strict-") as directory:
            tmp = Path(directory)
            if output_format == "mp3":
                source = tmp / "tone.wav"
                with wave.open(str(source), "wb") as audio:
                    audio.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
                    samples = array.array("h", (int(4000 * math.sin(2 * math.pi * 440 * i / 44100))
                                               for i in range(2 * 44100)))
                    if sys.byteorder != "little":
                        samples.byteswap()
                    audio.writeframes(samples.tobytes())
                target, expected, stream, extension = 32, 128, "oac", "mp3"
            else:
                source = ROOT / "tests/videos/big_buck_bunny_10s.mp4"
                target, expected, stream, extension = 1000, 800, "ovc", "mp4"
            output = tmp / ("strict." + extension)
            log = tmp / "mpv.log"
            socket = str(tmp / "ipc")
            process = subprocess.Popen([
                "mpv", "--no-config", "--load-scripts=no", "--scripts-clr",
                "--vo=null", "--ao=null", "--idle=yes", "-v",
                "--input-ipc-server=" + socket, "--log-file=" + str(log),
            ], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
            ipc = MpvIPC()
            started = False
            try:
                ipc.connect(socket)
                ipc.start()
                started = True
                def command(*args):
                    reply = ipc.send_command({"command": list(args)})
                    self.assertEqual(reply.error, "success")
                command("enable_event", "client-message")
                command("load-script", str(ROOT / "build/webm.lua"))
                self.assertIsNotNone(ipc.wait_for_event("webm-script-loaded", 10))
                command("script-message", "mpv-webm-set-options", json.dumps({
                    "output_format": output_format,
                    "target_filesize": target,
                    "strict_filesize_constraint": True,
                    "twopass": False,
                    "run_detached": False,
                    "display_progress": False,
                    "scale_height": 144,
                    "output_directory": str(tmp),
                    "output_template": "strict",
                    "additional_flags": "--no-config --scripts-clr",
                }))
                command("loadfile", str(source), "replace")
                self.assertIsNotNone(ipc.wait_for_event("file-loaded", 10))
                command("keypress", "Shift+W")
                self.assertIsNotNone(ipc.wait_for_event("webm-show-main-page", 10))
                time.sleep(1)
                command("keypress", "e")
                event = ipc.wait_for_event("webm-encode-finished", 60)
                self.assertIsNotNone(event, "encode did not finish")
                self.assertEqual(event.args, ["webm-encode-finished", "success"],
                                 log.read_text(errors="replace")[-4000:])
                self.assertTrue(output.is_file())
                self.assertGreater(output.stat().st_size, 100)
                text = log.read_text(errors="replace")
                command_line = next(line for line in text.splitlines()
                                    if "Command line: mpv " in line)
                for option in ("b", "minrate", "maxrate"):
                    self.assertIn(f"--{stream}opts-add={option}={expected}k", command_line)
                self.assertNotIn("nilk", command_line)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                if started:
                    ipc.stop()

    def test_video_strict_bitrate(self):
        self.encode("avc")

    def test_audio_only_strict_bitrate(self):
        self.encode("mp3")
