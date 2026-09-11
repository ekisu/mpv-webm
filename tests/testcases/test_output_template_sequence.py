import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
UTIL_MOON = REPO_ROOT / "src" / "util.moon"

# Stubs for the mpv globals used by src/util.moon. Template, output dir and
# media filename travel in argv so no test data is embedded in the file.
# utils.file_info hits the real filesystem, so collision handling is
# exercised for real. All scratch paths come from tempfile.
STUBS = r"""
mp = {
  get_property = function(name)
    local media = arg[3]
    if name == "filename" then return media end
    if name == "filename/no-ext" then return (media:gsub("%.[^%.]*$", "")) end
    if name == "media-title" then return "TITLE-" .. media end
    if name == "stream-open-filename" then return media end
    return ""
  end,
  get_property_native = function(name) return nil end,
  get_property_bool = function(name, default) return false end,
  get_property_osd = function(name) return "" end,
}

utils = {
  file_info = function(name)
    local handle = io.open(name, "rb")
    if handle ~= nil then
      handle:close()
      return { size = 0 }
    end
    return nil
  end,
  join_path = function(a, b)
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
  end,
}

msg = {
  verbose = function(...) end,
  info = function(...) end,
  warn = function(...) end,
}

options = {
  output_template = arg[1],
  scale_height = -1,
  target_filesize = 2500,
}
"""

DRIVER = r"""
local outdir = nil
if arg[4] ~= "nil" then outdir = arg[2] end
io.write(format_filename(1, 2, { audioCodec = "", outputExtension = "mp4" }, outdir))
"""


class TestOutputTemplateSequence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        for tool in ("lua", "moonc"):
            if shutil.which(tool) is None:
                raise unittest.SkipTest(f"required tool {tool!r} not found on PATH")
        cls._scratch = tempfile.TemporaryDirectory(prefix="mpv-webm-seq-")
        cls.addClassCleanup(cls._scratch.cleanup)
        # Compile the whole util.moon (not excerpts): the harness below
        # only relies on format_filename, which also exists on baseline,
        # so unfixed code fails assertions instead of failing to load.
        util_lua = Path(cls._scratch.name) / "util.lua"
        build = subprocess.run(
            ["moonc", "-o", str(util_lua), str(UTIL_MOON)],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if build.returncode != 0 or not util_lua.exists():
            raise AssertionError(
                f"moonc failed on src/util.moon:\n{build.stdout}\n{build.stderr}"
            )
        combined = Path(cls._scratch.name) / "combined.lua"
        combined.write_text(
            STUBS + util_lua.read_text(encoding="utf-8") + DRIVER,
            encoding="utf-8",
        )
        cls.combined = str(combined)

    def render(self, template, outdir=None, media="video.mp4", cwd=None):
        flag = "nil" if outdir is None else "dir"
        proc = subprocess.run(
            ["lua", self.combined, template, outdir or "", media, flag],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=cwd,
        )
        self.assertEqual(proc.returncode, 0, msg=f"harness failed: {proc.stderr}")
        return proc.stdout

    @staticmethod
    def touch(directory, name):
        Path(directory, name).write_bytes(b"x")

    def test_padded_counter_starts_at_1(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            self.assertEqual(self.render("clip_%04n", outdir), "clip_0001.mp4")

    def test_padded_counter_skips_existing(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            self.touch(outdir, "clip_0001.mp4")
            self.touch(outdir, "clip_0002.mp4")
            self.assertEqual(self.render("clip_%04n", outdir), "clip_0003.mp4")

    def test_padded_counter_fills_gaps(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            self.touch(outdir, "clip_0001.mp4")
            self.touch(outdir, "clip_0003.mp4")
            self.assertEqual(self.render("clip_%04n", outdir), "clip_0002.mp4")

    def test_unpadded_counter_counts_past_nine(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            for i in range(1, 10):
                self.touch(outdir, f"clip_{i}.mp4")
            self.assertEqual(self.render("clip_%n", outdir), "clip_10.mp4")

    def test_multiple_counters_share_one_index(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            self.assertEqual(self.render("%04n_%02n", outdir), "0001_01.mp4")
            self.touch(outdir, "0001_01.mp4")
            self.assertEqual(self.render("%04n_%02n", outdir), "0002_02.mp4")

    def test_template_without_counter_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            self.touch(outdir, "clip.mp4")
            # No %n: previous behavior is kept, even if the file exists.
            self.assertEqual(self.render("clip", outdir), "clip.mp4")

    def test_hidden_counter_does_not_search(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            # The %04n sits inside %X{...}, which expands to "" for local
            # files, swallowing the counter: no numbering search may run.
            self.touch(outdir, "clip.mp4")
            self.touch(outdir, "clip_0001.mp4")
            self.assertEqual(self.render("clip%X{-%04n}", outdir), "clip.mp4")

    def test_counter_like_text_from_media_filename_is_not_expanded(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            rendered = self.render("%F_%04n", outdir, media="sample_%04n_src.mp4")
            self.assertEqual(rendered, "sample_%04n_src_0001.mp4")

    def test_percent_captures_from_media_filename_stay_literal(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            rendered = self.render("%F", outdir, media="a%1b%0c.mp4")
            self.assertEqual(rendered, "a%1b%0c.mp4")

    def test_escaped_percent_stays_literal(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            self.assertEqual(self.render("clip_%%n", outdir), "clip_%n.mp4")

    def test_current_dir_collisions(self):
        with tempfile.TemporaryDirectory(prefix="mpv-webm-out-") as outdir:
            # An empty output_directory means the mpv working directory:
            # "" must be collision-checked, not answered with index 1.
            self.assertEqual(self.render("clip_%04n", "", cwd=outdir), "clip_0001.mp4")
            self.touch(outdir, "clip_0001.mp4")
            self.assertEqual(self.render("clip_%04n", "", cwd=outdir), "clip_0002.mp4")

    def test_counter_without_output_dir_uses_first_index(self):
        self.assertEqual(self.render("clip_%04n"), "clip_0001.mp4")
