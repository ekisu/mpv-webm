from collections import deque
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
import time
import unittest

from tests.mpv_ipc import MpvIPC


ROOT = Path(__file__).resolve().parents[2]


class BaseTestCase(unittest.TestCase):
    # GUI subclasses supply a real video output and an isolated DISPLAY.
    mpv_executable = "mpv"
    mpv_args = ()
    mpv_env = None

    def setUp(self):
        super().setUp()
        scratch = tempfile.TemporaryDirectory(prefix="mpv-webm-test-")
        self.addCleanup(scratch.cleanup)
        self.tempdir = Path(scratch.name)
        self._log = deque(maxlen=4000)
        self._log_lock = threading.Lock()
        self.mpv_ipc = MpvIPC()
        self.log_reader = None
        socket_address = str(self.tempdir / "ipc")
        args = [
            self.mpv_executable, "-v", "--no-config", "--vo=null", "--ao=null",
            "--load-scripts=no", "--scripts-clr", "--idle=yes",
            "--input-ipc-server=" + socket_address,
            *self.mpv_args,
        ]
        self.mpv_process = subprocess.Popen(
            args, cwd=self.tempdir, env=self.mpv_env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        self.addCleanup(self._stop_player)
        self.log_reader = threading.Thread(target=self._read_log, daemon=True)
        self.log_reader.start()
        try:
            self.mpv_ipc.connect(socket_address)
            self.mpv_ipc.start()
            self.sendCommandToMpv({"command": ["enable_event", "client-message"]})
            cursor = self.mpv_ipc.event_cursor
            self.sendCommandToMpv({"command": ["load-script", str(ROOT / "build/webm.lua")]})
            self.waitForEvent("webm-script-loaded", after=cursor)
            self.updateScriptOptions({
                "output_directory": str(self.tempdir),
                "additional_flags": "--no-config --scripts-clr",
                "display_progress": False,
                "run_detached": False,
            })
        except Exception as error:
            self.fail(f"Could not initialize mpv: {error}\n{self.getLog()}")

    def _read_log(self):
        for line in self.mpv_process.stdout:
            with self._log_lock:
                self._log.append(line.decode(errors="replace"))

    def getLog(self):
        with self._log_lock:
            return "".join(self._log)

    def _stop_player(self):
        # Include encoder children if a failed/timed-out test left one running.
        try:
            os.killpg(self.mpv_process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.mpv_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(self.mpv_process.pid, signal.SIGKILL)
            self.mpv_process.wait(timeout=5)
        self.mpv_ipc.stop()
        if self.log_reader is not None:
            self.log_reader.join(timeout=5)
        self.mpv_process.stdout.close()

    def sendCommandToMpv(self, data, timeout=10):
        try:
            reply = self.mpv_ipc.send_command(data, timeout)
        except (TimeoutError, ConnectionError) as error:
            self.fail(f"mpv command {data!r} failed: {error}\n{self.getLog()}")
        self.assertEqual(reply.error, "success", f"{data!r}: {reply.error}\n{self.getLog()}")
        return reply

    def scriptMessage(self, name, *args, event=None, timeout=10):
        cursor = self.mpv_ipc.event_cursor
        self.sendCommandToMpv({"command": ["script-message", name, *args]})
        if event is not None:
            return self.waitForEvent(event, timeout, after=cursor)

    def updateScriptOptions(self, new_options):
        self.scriptMessage("mpv-webm-set-options", json.dumps(new_options), event="webm-options-set")

    def openTestVideoFile(self, path):
        cursor = self.mpv_ipc.event_cursor
        self.sendCommandToMpv({"command": ["loadfile", str(Path(path).resolve()), "replace"]})
        self.waitForEvent("file-loaded", after=cursor)
        self.setProperty("pause", True)

    def sendKeyPress(self, key, event=None):
        cursor = self.mpv_ipc.event_cursor
        self.sendCommandToMpv({"command": ["keypress", key]})
        if event is not None:
            return self.waitForEvent(event, after=cursor)

    def setProperty(self, name, value):
        self.sendCommandToMpv({"command": ["set_property", name, value]})

    def getProperty(self, name):
        return self.sendCommandToMpv({"command": ["get_property", name]}).data

    def getState(self):
        event = self.scriptMessage("mpv-webm-get-state", event="webm-state")
        return json.loads(event.args[1])

    def setRange(self, start, end, region=None):
        data = {"startTime": start, "endTime": end}
        if region is not None:
            data["region"] = region
        self.scriptMessage("mpv-webm-set-range", json.dumps(data), event="webm-range-set")

    def encodeClip(self, start, end, region=None, options=None, timeout=60):
        if options is not None:
            self.updateScriptOptions(options)
        self.setRange(start, end, region)
        event = self.scriptMessage("mpv-webm-encode", event="webm-encode-finished", timeout=timeout)
        self.assertEqual(event.args, ["webm-encode-finished", "success"], self.getLog())
        return event

    def waitForEvent(self, event_name, timeout=5, after=None):
        try:
            event = self.mpv_ipc.wait_for_event(event_name, timeout, after=after)
        except ConnectionError as error:
            self.fail(f"Waiting for {event_name}: {error}\n{self.getLog()}")
        self.assertIsNotNone(event, f"No {event_name} event within {timeout}s\n{self.getLog()}")
        return event

    def waitUntil(self, predicate, description, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            if self.mpv_process.poll() is not None:
                break
            time.sleep(0.02)
        self.fail(f"Timed out waiting for {description}\n{self.getLog()}")

    def runTool(self, *args, timeout=30):
        result = subprocess.run(args, cwd=self.tempdir, env=self.mpv_env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def createVideo(self, name="source.mkv", size="320x180", duration=3, color=None):
        source = self.tempdir / name
        pattern = f"color=c={color}:s={size}:r=10:d={duration}" if color else f"testsrc2=size={size}:rate=10:duration={duration}"
        self.runTool("ffmpeg", "-v", "error", "-f", "lavfi", "-i", pattern,
                     "-c:v", "ffv1", str(source))
        return source

    def decodeVideo(self, path):
        return self.runTool("ffmpeg", "-v", "error", "-i", str(path),
                            "-pix_fmt", "rgb24", "-f", "rawvideo", "-")

    def probeVideo(self, path):
        return json.loads(self.runTool("ffprobe", "-v", "error", "-show_streams",
                                      "-show_format", "-of", "json", str(path)))
