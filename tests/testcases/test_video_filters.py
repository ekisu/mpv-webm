"""Exercise production video-filter assembly with controlled mpv properties."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HARNESS = r"""
mp = {
    get_property: (name) -> ({brightness: arg[2], contrast: arg[3], saturation: arg[4]})[name]
    get_property_number: (name, default) -> tonumber(mp.get_property(name)) or default
    get_property_native: (name) -> {{name: "hflip", enabled: true, params: {}}}
}
msg = {verbose: -> nil}
options = {
    apply_current_filters: arg[1] == "yes"
    force_square_pixels: false
    scale_height: 144
    fps: 10
}
format = {
    getPreFilters: => {"pre-filter"}
    getPostFilters: => {"post-filter"}
}
region = {w: 100, h: 80, x: 2, y: 4, is_valid: => true}
for filter in *get_video_filters(format, region)
    io.write(filter, "\n")
"""


@unittest.skipUnless(shutil.which("lua") and shutil.which("moonc"),
                     "requires Lua and MoonScript")
class TestVideoFilters(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="mpv-webm-filters-")
        cls.addClassCleanup(cls.scratch.cleanup)
        source = "local mp, options, msg\n" + "\n".join(
            (ROOT / name).read_text() for name in ("src/util.moon", "src/encode.moon"))
        moon = Path(cls.scratch.name) / "filters.moon"
        cls.lua = Path(cls.scratch.name) / "filters.lua"
        moon.write_text(source + "\n" + HARNESS)
        subprocess.run(["moonc", "-o", str(cls.lua), str(moon)], check=True,
                       capture_output=True, timeout=30)

    def filters(self, enabled, brightness=0, contrast=0, saturation=0):
        result = subprocess.run(["lua", str(self.lua), "yes" if enabled else "no",
                                 str(brightness), str(contrast), str(saturation)],
                                check=True, capture_output=True, text=True, timeout=10)
        return result.stdout.splitlines()

    def test_disabled_filters_exclude_equalizer_and_current_vf(self):
        self.assertEqual(self.filters(False, 50, 50, -100), [
            "pre-filter", "lavfi-crop=100:80:2:4", "lavfi-scale=-2:144",
            "fps=10", "post-filter",
        ])

    def test_enabled_filters_preserve_order_and_equalizer_values(self):
        self.assertEqual(self.filters(True, 50, 50, -100), [
            "pre-filter", "hflip", "lavfi-crop=100:80:2:4", "lavfi-scale=-2:144",
            "fps=10", "lavfi-eq=contrast=1.5:saturation=0:brightness=0.75", "post-filter",
        ])

    def test_default_equalizer_does_not_add_identity_filter(self):
        self.assertEqual(self.filters(True), [
            "pre-filter", "hflip", "lavfi-crop=100:80:2:4", "lavfi-scale=-2:144",
            "fps=10", "post-filter",
        ])
