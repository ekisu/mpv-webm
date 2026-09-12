"""Isolated real X11 input for mpv integration tests (requires Xvfb/xdotool)."""

import os
import select
import shutil
import subprocess
import tempfile
import time


class XvfbDisplay:
    """Own an X server; ``env`` is a subprocess-ready environment.

    ``logs`` remains readable after exit, including failed startup. Temporary
    log files are removed on exit. Window geometry uses lowercase integer keys
    (window, x, y, width, height, screen); mouse coordinates are window-relative.
    """

    def __init__(self, timeout=5):
        self.timeout = timeout
        self.env = None
        self.display = None
        self.process = None
        self._log = None
        self._logs = ""

    @property
    def logs(self):
        if self._log is not None:
            return os.pread(self._log.fileno(), os.fstat(self._log.fileno()).st_size, 0).decode(
                "utf-8", errors="replace")
        return self._logs

    def __enter__(self):
        if self.process is not None:
            raise RuntimeError("XvfbDisplay is already running")
        for executable in ("Xvfb", "xdotool"):
            if shutil.which(executable) is None:
                raise RuntimeError("Required GUI test dependency is missing: " + executable)
        read_fd, write_fd = os.pipe()
        try:
            self._log = tempfile.TemporaryFile(prefix="mpv-xvfb-", mode="w+b")
            self.process = subprocess.Popen(
                ["Xvfb", "-displayfd", str(write_fd), "-screen", "0",
                 "1280x1024x24", "-nolisten", "tcp", "-noreset"],
                pass_fds=(write_fd,), stdout=self._log, stderr=self._log,
            )
            os.close(write_fd)
            write_fd = None
            deadline = time.monotonic() + self.timeout
            response = b""
            while b"\n" not in response:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("Timed out waiting for Xvfb -displayfd readiness")
                readable, _, _ = select.select([read_fd], [], [], remaining)
                if not readable:
                    raise TimeoutError("Timed out waiting for Xvfb -displayfd readiness")
                chunk = os.read(read_fd, 128)
                if not chunk:
                    raise RuntimeError("Xvfb exited before announcing a display")
                response += chunk
            number = response.strip()
            if not number.isdigit():
                raise RuntimeError("Invalid Xvfb display response: {!r}".format(response))
            self.display = ":" + number.decode("ascii")
            self.env = os.environ.copy()
            self.env.pop("WAYLAND_DISPLAY", None)
            self.env["DISPLAY"] = self.display
            # The displayfd reply signals server readiness; confirm a client connects.
            self._xdotool("getdisplaygeometry")
            return self
        except BaseException as error:
            self.close()
            if isinstance(error, Exception):
                raise RuntimeError("Could not start Xvfb: {}\n{}".format(error, self.logs)) from error
            raise
        finally:
            os.close(read_fd)
            if write_fd is not None:
                os.close(write_fd)

    def close(self):
        try:
            if self.process is not None:
                if self.process.poll() is None:
                    self.process.terminate()
                    try:
                        self.process.wait(timeout=self.timeout)
                    except subprocess.TimeoutExpired:
                        self.process.kill()
                        self.process.wait(timeout=self.timeout)
                self.process = None
        finally:
            if self._log is not None:
                self._logs = self.logs
                self._log.close()
                self._log = None
            self.env = None
            self.display = None

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def _xdotool(self, *args, timeout=None, check=True):
        if self.process is None or self.process.poll() is not None:
            raise RuntimeError("Xvfb is not running\n" + self.logs)
        result = subprocess.run(
            ["xdotool", *map(str, args)], env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            timeout=self.timeout if timeout is None else timeout,
        )
        if check and result.returncode:
            raise RuntimeError("xdotool {} failed: {}\nXvfb: {}".format(
                " ".join(map(str, args)), result.stderr, self.logs))
        return result

    def wait_for_window(self, pid, title=None, window_class=None, timeout=None):
        """Wait for a visible PID-owned window; optional filters are X regexes."""
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        args = ["search", "--onlyvisible", "--all", "--pid", str(pid)]
        # xdotool search accepts one pattern; intersect independent searches
        # when both a title and a class pattern were requested.
        searches = []
        if title is not None:
            searches.append(args + ["--name", title])
        if window_class is not None:
            searches.append(args + ["--class", window_class])
        if not searches:
            searches.append(args)
        last_error = ""
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("No visible X window for PID {}: {}\nXvfb: {}".format(
                    pid, last_error, self.logs))
            matches = None
            for search in searches:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                result = self._xdotool(*search, timeout=remaining, check=False)
                found = set(result.stdout.splitlines()) if result.returncode == 0 else set()
                matches = found if matches is None else matches & found
                last_error = result.stderr.strip()
            else:
                if matches:
                    return min(map(int, matches))
            # Poll a real condition rather than delaying every successful startup.
            time.sleep(min(0.02, max(0, deadline - time.monotonic())))

    def geometry(self, window):
        result = self._xdotool("getwindowgeometry", "--shell", window)
        return {key.lower(): int(value) for key, value in
                (line.split("=", 1) for line in result.stdout.splitlines())}

    def move_mouse(self, window, x, y):
        """Generate X motion, then confirm the pointer reached the coordinates.

        Application-side processing remains asynchronous; callers should wait
        for the corresponding mpv state before asserting it.
        """
        geometry = self.geometry(window)
        self._xdotool("mousemove", "--window", window, x, y)
        result = self._xdotool("getmouselocation", "--shell")
        location = dict(line.split("=", 1) for line in result.stdout.splitlines())
        if (int(location["X"]), int(location["Y"])) != (geometry["x"] + x, geometry["y"] + y):
            raise RuntimeError("X pointer did not reach requested window coordinates: " + result.stdout)

    def key(self, window, key):
        """Deliver a key (xdotool syntax, e.g. 'c' or 'Escape') to the window."""
        self._xdotool("key", "--window", window, "--clearmodifiers", key)
