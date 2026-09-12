from .base_test_case import BaseTestCase


class TestGifSubtitles(BaseTestCase):
    def test_visible_subtitles_are_included_in_the_palette(self):
        plain = self.createVideo(color="blue")
        srt = self.tempdir / "caption.srt"
        srt.write_text("1\n00:00:00,500 --> 00:00:02,500\nSUBTITLE TEST\n")
        ass = self.tempdir / "caption.ass"
        self.runTool("ffmpeg", "-v", "error", "-i", str(srt), str(ass))
        for subtitle in (srt, ass):
            source = self.tempdir / (subtitle.suffix[1:] + ".mkv")
            self.runTool("ffmpeg", "-v", "error", "-i", str(plain), "-i", str(subtitle),
                         "-map", "0:v", "-map", "1:0", "-c:v", "copy",
                         "-c:s", subtitle.suffix[1:], str(source))
            self.openTestVideoFile(source)
            self.setProperty("sub-scale", 3)
            for dither in (2, 6):
                with self.subTest(subtitle=subtitle.suffix, dither=dither):
                    frames = {}
                    for visibility in ("off", "on", "hidden"):
                        self.setProperty("sid", "no" if visibility == "off" else 1)
                        self.setProperty("sub-visibility", visibility != "hidden")
                        name = f"{subtitle.suffix[1:]}-{dither}-{visibility}"
                        self.encodeClip(1, 2, options={
                            "output_format": "gif", "output_template": name,
                            "scale_height": 90, "fps": 10, "gif_dither": dither,
                        })
                        frames[visibility] = self.decodeVideo(self.tempdir / (name + ".gif"))
                    frame_size = 160 * 90 * 3
                    self.assertEqual(len(frames["on"]), 10 * frame_size)
                    self.assertEqual(len(frames["off"]), len(frames["on"]))
                    self.assertEqual(frames["hidden"], frames["off"])
                    # Inspect a middle frame after subtitle initialization.
                    on = frames["on"][5 * frame_size:6 * frame_size]
                    off = frames["off"][5 * frame_size:6 * frame_size]
                    self.assertNotEqual(on, off, "visible subtitles were not burned in")
                    def bright_pixels(data):
                        return sum(all(c > 100 for c in data[i:i+3])
                                   for i in range(0, len(data), 3))
                    self.assertEqual(bright_pixels(off), 0)
                    self.assertGreater(bright_pixels(on), 20)
