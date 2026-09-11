"""Regression tests for issue #140: right/bottom crop one pixel short.

Exercises the actual compiled src/video_to_screen.moon (via moonc)
with lua, not a mirrored Python reimplementation. Each test injects a
known geometry into the compiled module and calls the real
VideoPoint.set_from_screen / Region.set_from_points.

Run focused suite from repo root:
    python -m unittest tests.testcases.test_crop_mapping -v
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

def _repo_root():
    return Path(__file__).resolve().parents[2]

def _find_moonc():
    return shutil.which("moonc")

def _find_lua():
    return shutil.which("lua")

class TestCropMapping(unittest.TestCase):
    compiled_src = None
    tmpdir = None

    @classmethod
    def setUpClass(cls):
        moonc = _find_moonc()
        lua = _find_lua()
        if not moonc:
            raise unittest.SkipTest("moonc not found")
        if not lua:
            raise unittest.SkipTest("lua not found")
        cls.lua_bin = lua
        src = _repo_root() / "src" / "video_to_screen.moon"
        cls.tmpdir = tempfile.TemporaryDirectory(prefix="crop140-")
        out = Path(cls.tmpdir.name) / "video_to_screen.lua"
        proc = subprocess.run([moonc, "-o", str(out), str(src)], capture_output=True, text=True, timeout=60)
        if proc.returncode != 0 or not out.is_file():
            cls.tmpdir.cleanup()
            raise AssertionError("moonc failed: " + proc.stderr[:500])
        cls.compiled_src = out.read_text()

    @classmethod
    def tearDownClass(cls):
        if cls.tmpdir is not None:
            cls.tmpdir.cleanup()

    def _run_driver(self, dims, expressions):
        tlx, tly, brx, bry, vw, vh = dims
        hook = "\n__TEST__ = {VideoPoint=VideoPoint, Region=Region, set_dims=function(d) _video_dimensions=d; dimensions_changed=false end}\n"
        driver = "__TEST__.set_dims({top_left={x=" + str(tlx) + ",y=" + str(tly) + "}, bottom_right={x=" + str(brx) + ",y=" + str(bry) + "}, ratios={w=" + str(vw) + "/(" + str(brx) + "-" + str(tlx) + "), h=" + str(vh) + "/(" + str(bry) + "-" + str(tly) + ")}})\n" + expressions
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lua", delete=False, dir=self.tmpdir.name) as h:
            h.write(self.compiled_src)
            h.write(hook)
            h.write(driver)
            path = h.name
        proc = subprocess.run([self.lua_bin, path], capture_output=True, text=True, timeout=30)
        self.assertEqual(proc.returncode, 0, "lua failed: " + proc.stderr[:1000])
        return [ln for ln in proc.stdout.splitlines() if ln.strip()]

    def _map_points(self, dims, points):
        body = ""
        for sx, sy in points:
            body += "do local p = __TEST__.VideoPoint(); p:set_from_screen(" + str(sx) + "," + str(sy) + "); print(string.format(\"%d %d\", p.x, p.y)) end\n"
        lines = self._run_driver(dims, body)
        self.assertEqual(len(lines), len(points))
        out = []
        for ln in lines:
            a, b = ln.split()
            out.append((int(a), int(b)))
        return out

    def _region(self, dims, first, second):
        body = "do local a = __TEST__.VideoPoint(); a:set_from_screen(" + str(first[0]) + "," + str(first[1]) + "); local b = __TEST__.VideoPoint(); b:set_from_screen(" + str(second[0]) + "," + str(second[1]) + "); local r = __TEST__.Region(); r:set_from_points(a, b); print(string.format(\"%d %d %d %d\", r.x, r.y, r.w, r.h)) end\n"
        lines = self._run_driver(dims, body)
        self.assertEqual(len(lines), 1)
        x, y, w, h = [int(v) for v in lines[0].split()]
        return x, y, w, h

    def test_full_edge_1to1(self):
        dims = (0, 0, 1280, 720, 1280, 720)
        pts = self._map_points(dims, [(0, 0), (1279, 719)])
        self.assertEqual(pts[0], (0, 0))
        self.assertEqual(pts[1], (1280, 720))
        self.assertEqual(self._region(dims, (0, 0), (1279, 719)), (0, 0, 1280, 720))

    def test_interior_unchanged_1to1(self):
        dims = (0, 0, 1280, 720, 1280, 720)
        pts = self._map_points(dims, [(100, 100), (1278, 718)])
        self.assertEqual(pts[0], (100, 100))
        self.assertEqual(pts[1], (1278, 718))

    def test_reverse_drag_full_frame(self):
        dims = (0, 0, 1280, 720, 1280, 720)
        self.assertEqual(self._region(dims, (1279, 719), (0, 0)), (0, 0, 1280, 720))

    def test_downscaled(self):
        dims = (0, 0, 640, 360, 1280, 720)
        pts = self._map_points(dims, [(100, 100), (639, 359)])
        self.assertEqual(pts[0], (200, 200))
        self.assertEqual(pts[1], (1280, 720))

    def test_letterboxed(self):
        dims = (100, 50, 740, 410, 1280, 720)
        pts = self._map_points(dims, [(100, 50), (200, 150), (739, 409)])
        self.assertEqual(pts[0], (0, 0))
        self.assertEqual(pts[1], (200, 200))
        self.assertEqual(pts[2], (1280, 720))

    def test_degenerate_1px_display(self):
        dims = (0, 0, 1, 1, 1280, 720)
        pts = self._map_points(dims, [(0, 0)])
        self.assertEqual(pts[0], (0, 0))


if __name__ == "__main__":
    unittest.main()
