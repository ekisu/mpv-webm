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
    def setUp(self):
        super().setUp()
        self.stub = self.tempdir / "stub-curl"
        self.stub.write_text(STUB_CURL)
        self.stub.chmod(self.stub.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    def encodeAndUpload(self, **options):
        self.openTestVideoFile(self.createVideo(size="320x180", duration=3))
        settings = {
            "output_format": "avc",
            "output_template": "clip",
            "display_progress": False,
            "run_detached": False,
            "upload_curl_path": str(self.stub),
        }
        settings.update(options)
        self.updateScriptOptions(settings)
        self.setRange(1, 2)
        event = self.scriptMessage("mpv-webm-upload", event="webm-upload-finished", timeout=60)
        self.assertEqual(event.args, ["webm-upload-finished", "done"], self.getLog())
        self.assertTrue((self.tempdir / "clip.mp4").exists())
        return (self.tempdir / "stub-args.txt").read_text()

    def test_catbox_upload(self):
        args = self.encodeAndUpload(upload_host="catbox")
        self.assertIn("https://catbox.moe/user/api.php", args)
        self.assertIn("reqtype=fileupload", args)
        self.assertIn("fileToUpload=@", args)
        # catbox is permanent and optional account-based: no expiry, no hash here.
        self.assertNotIn("time=", args)
        self.assertNotIn("userhash=", args)

    def test_litterbox_upload_sends_expiry(self):
        args = self.encodeAndUpload(upload_host="litterbox", litterbox_time="72h")
        self.assertIn("https://litterbox.catbox.moe/resources/internals/api.php", args)
        self.assertIn("time=72h", args)
        self.assertNotIn("userhash=", args)

    def test_upload_aborts_without_times(self):
        self.openTestVideoFile(self.createVideo(size="320x180", duration=3))
        self.updateScriptOptions({
            "output_format": "avc",
            "output_template": "clip",
            "upload_curl_path": str(self.stub),
        })
        self.setRange(-1, -1)
        # No encode should start, so no upload-finished event should arrive.
        self.scriptMessage("mpv-webm-upload")
        self.assertIsNone(self.mpv_ipc.wait_for_event("webm-upload-finished", 1), self.getLog())
        self.assertFalse((self.tempdir / "stub-args.txt").exists())
