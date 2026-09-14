"""Integration coverage for the "encode & upload" flow (issue #228).

The network is replaced by a stub curl, so these tests exercise the real script
path — keybinding handler, encoder, async subprocess, progress/done states —
without depending on Catbox being reachable.
"""

import stat

from .base_test_case import BaseTestCase


# Handles --version (the availability probe) and the real invocation: writes the
# URL to the -o target, a progress meter to the --stderr target, and 200 to
# stdout. Records its arguments so the test can assert the request shape.
STUB_CURL = r"""#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "curl 8.0.0"
  exit 0
fi
printf '%s\n' "$@" > "$(dirname "$0")/stub-args.txt"
out=""
err=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2;;
    --stderr) err="$2"; shift 2;;
    *) shift;;
  esac
done
[ -n "$out" ] && printf 'https://files.catbox.moe/stub123.webm\n' > "$out"
[ -n "$err" ] && printf '#### 100.0%%\n' > "$err"
printf '200'
exit 0
"""


class TestUpload(BaseTestCase):
    def makeStubCurl(self):
        stub = self.tempdir / "stub-curl"
        stub.write_text(STUB_CURL)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        return stub

    def upload(self):
        event = self.scriptMessage("mpv-webm-upload", event="webm-upload-finished", timeout=60)
        self.assertEqual(event.args, ["webm-upload-finished", "done"], self.getLog())
        return (self.tempdir / "stub-args.txt").read_text()

    def closeUploadPage(self):
        self.sendKeyPress("ESC")
        self.waitUntil(lambda: self.getState()["mainVisible"], "main page after closing upload")

    def test_encode_and_upload_both_hosts(self):
        stub = self.makeStubCurl()
        self.openTestVideoFile(self.createVideo(size="320x180", duration=3))

        cases = (
            ("catbox", "24h", ["https://catbox.moe/user/api.php"], ["time=", "userhash="]),
            ("litterbox", "72h",
             ["https://litterbox.catbox.moe/resources/internals/api.php", "time=72h"], ["userhash="]),
        )
        for host, litterbox_time, present, absent in cases:
            with self.subTest(host=host):
                self.updateScriptOptions({
                    "output_format": "avc",
                    "output_template": "clip",
                    "display_progress": False,
                    "run_detached": False,
                    "upload_host": host,
                    "litterbox_time": litterbox_time,
                    "upload_curl_path": str(stub),
                })
                self.setRange(1, 2)
                args = self.upload()

                for token in present:
                    self.assertIn(token, args)
                for token in absent:
                    self.assertNotIn(token, args)
                self.assertIn("reqtype=fileupload", args)
                self.assertIn("fileToUpload=@", args)
                self.assertTrue((self.tempdir / "clip.mp4").exists())

                self.closeUploadPage()

    def test_upload_aborts_without_times(self):
        self.makeStubCurl()
        self.openTestVideoFile(self.createVideo(size="320x180", duration=3))
        self.updateScriptOptions({
            "output_format": "avc",
            "output_template": "clip",
            "upload_curl_path": str(self.tempdir / "stub-curl"),
        })
        self.setRange(-1, -1)
        # No encode should start, so no upload-finished event should arrive.
        self.scriptMessage("mpv-webm-upload")
        self.assertIsNone(self.mpv_ipc.wait_for_event("webm-upload-finished", 1), self.getLog())
        self.assertFalse((self.tempdir / "stub-args.txt").exists())
