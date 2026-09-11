import json
import re
import subprocess
import tempfile
import time
import unittest
import uuid
from pathlib import Path

from tests.mpv_ipc import MpvIPC


REPO_ROOT = Path(__file__).resolve().parents[2]
ENCODE_MOON = REPO_ROOT / "src" / "encode.moon"
TEST_VIDEO = REPO_ROOT / "tests" / "videos" / "big_buck_bunny_10s.mp4"
# 10s clip, so target_filesize=1000kB means 1000*8/10 = 800kbit/s.
TARGET_FILESIZE = 1000
CLIP_LENGTH = 10
EXPECTED_BITRATE = TARGET_FILESIZE * 8 // CLIP_LENGTH


def read_source():
    return ENCODE_MOON.read_text(encoding="utf-8")


def strict_block(source):
    """Return the strict minrate/maxrate branch body inside encode()."""
    # NOTE: calculate_bitrate() also mentions strict_filesize_constraint, so
    # anchor on the bare `if` line (no trailing `and ...`) used by encode().
    match = re.search(r"if options\.strict_filesize_constraint\r?\n", source)
    if match is None:
        raise AssertionError("strict_filesize_constraint block not found")
    start = match.start()
    end = source.find("\n\t\telse", start)
    if end == -1:
        raise AssertionError("end of strict block not found")
    return source[start:end]


def select_strict_bitrate(has_video_codec, video_bitrate, audio_bitrate):
    """Python mirror of the strict-bitrate selection in src/encode.moon."""
    return video_bitrate if has_video_codec else audio_bitrate


def run_strict_encode_command_line(testcase, output_format):
    """Boot mpv (stdout drained) and capture the strict encode command line.

    Returns the logged `Command line: mpv ...` string. The encode itself is
    not awaited; the child is terminated once the command line is captured.
    """
    script = REPO_ROOT / "build" / "webm.lua"
    testcase.assertTrue(script.exists(), "build/webm.lua missing; run make first")
    testcase.assertTrue(TEST_VIDEO.exists(), f"test video missing: {TEST_VIDEO}")

    tmpdir = tempfile.mkdtemp(prefix="mpv-webm-strict-test-")
    socket_address = f"/tmp/mpvsocket-strict-{uuid.uuid4()}"
    log_path = Path(tmpdir) / "mpv.log"
    args = [
        "mpv", "--no-config", "--vo=null", "--ao=null",
        "--load-scripts=no", "--idle=yes",
        f"--input-ipc-server={socket_address}",
        f"--log-file={log_path}", "-v",
    ]
    # Drain stdout to a file: mpv -v over a PIPE stalls and hangs the test.
    with open(Path(tmpdir) / "stdout.log", "wb") as out:
        proc = subprocess.Popen(args, stdout=out, stderr=subprocess.STDOUT)
        try:
            ipc = MpvIPC()
            ipc.connect(socket_address)
            ipc.start()
            try:
                ipc.send_command({"command": ["enable_event", "client-message"]})
                ipc.send_command({"command": ["load-script", str(script)]})
                testcase.assertTrue(
                    ipc.wait_for_event("webm-script-loaded", 15),
                    "script did not load",
                )
                ipc.send_command({"command": ["script-message",
                    "mpv-webm-set-options", json.dumps({
                        "output_format": output_format,
                        "target_filesize": TARGET_FILESIZE,
                        "strict_filesize_constraint": True,
                        "twopass": False,
                        "run_detached": False,
                        "display_progress": "no",
                        "output_directory": tmpdir,
                    })]})
                ipc.send_command({"command": ["loadfile", str(TEST_VIDEO), "replace"]})
                testcase.assertTrue(
                    ipc.wait_for_event("file-loaded", 15), "file did not load")
                ipc.send_command({"command": ["keypress", "Shift+W"]})
                testcase.assertTrue(
                    ipc.wait_for_event("webm-show-main-page", 15),
                    "main page did not open",
                )
                time.sleep(1)
                ipc.send_command({"command": ["keypress", "e"]})
                deadline = time.time() + 60
                while time.time() < deadline:
                    text = log_path.read_text(errors="replace") \
                        if log_path.exists() else ""
                    match = re.search(r"Command line: mpv .*", text)
                    if match and "minrate=" in match.group(0):
                        return match.group(0)
                    time.sleep(0.2)
                testcase.fail("strict encode command line was not logged")
            finally:
                ipc.stop()
        finally:
            proc.terminate()
            proc.wait(timeout=15)


class TestStrictFilesize(unittest.TestCase):
    def test_no_undefined_bitrate_in_strict_flags(self):
        block = strict_block(read_source())
        self.assertIn("minrate", block)
        self.assertIn("maxrate", block)
        # Regression (see issue #48 strict-size reports): an earlier refactor
        # left `#{bitrate}` referencing an undefined variable, which encodes
        # as minrate=nilk / maxrate=nilk and makes ffmpeg reject the flags.
        self.assertNotRegex(block, r"#\{bitrate\}")

    def test_strict_flags_use_matching_stream_bitrate(self):
        block = strict_block(read_source())
        # The constrained stream is ovc for video formats, oac for audio-only.
        self.assertIn('format.videoCodec != "" and "ovc" or "oac"', block)
        # ...and its min/max rates must come from calculate_bitrate's
        # video_bitrate / audio_bitrate return values.
        self.assertIn("video_bitrate", block)
        self.assertIn("audio_bitrate", block)
        minrate_vars = set(re.findall(r"minrate=#\{(\w+)\}", block))
        maxrate_vars = set(re.findall(r"maxrate=#\{(\w+)\}", block))
        self.assertTrue(minrate_vars, "no minrate bitrate variable found")
        self.assertEqual(minrate_vars, maxrate_vars)
        self.assertTrue(
            minrate_vars <= {"video_bitrate", "audio_bitrate", "strict_bitrate"},
            f"unexpected bitrate variable(s): {minrate_vars}",
        )

    def test_strict_bitrate_selection_video(self):
        # Video formats constrain the video stream.
        self.assertEqual(select_strict_bitrate(True, 800, 64), 800)

    def test_strict_bitrate_selection_audio_only(self):
        # Audio-only formats (e.g. mp3) constrain the audio stream.
        self.assertEqual(select_strict_bitrate(False, None, 800), 800)


class TestStrictFilesizeCommandLine(unittest.TestCase):
    def test_strict_video_minmax_match_video_bitrate(self):
        cmdline = run_strict_encode_command_line(self, "avc")
        self.assertIn(f"--ovcopts-add=b={EXPECTED_BITRATE}k", cmdline)
        self.assertIn(f"--ovcopts-add=minrate={EXPECTED_BITRATE}k", cmdline)
        self.assertIn(f"--ovcopts-add=maxrate={EXPECTED_BITRATE}k", cmdline)
        self.assertNotIn("nilk", cmdline)

    def test_strict_audio_only_minmax_match_audio_bitrate(self):
        cmdline = run_strict_encode_command_line(self, "mp3")
        self.assertIn(f"--oacopts-add=b={EXPECTED_BITRATE}k", cmdline)
        self.assertIn(f"--oacopts-add=minrate={EXPECTED_BITRATE}k", cmdline)
        self.assertIn(f"--oacopts-add=maxrate={EXPECTED_BITRATE}k", cmdline)
        self.assertNotIn("nilk", cmdline)


if __name__ == "__main__":
    unittest.main()
