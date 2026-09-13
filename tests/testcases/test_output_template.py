from .base_test_case import BaseTestCase


def _avc_options(template):
    return {
        "output_format": "avc",
        "twopass": False,
        "target_filesize": 100,
        "scale_height": -1,
        "output_template": template,
    }


FRAME_SIZE = 320 * 180 * 3


class TestOutputTemplate(BaseTestCase):
    def assertValidClip(self, path):
        self.assertTrue(path.is_file(), self.getLog())
        self.assertGreater(path.stat().st_size, 0, self.getLog())
        decoded = self.decodeVideo(path)
        self.assertGreater(len(decoded), 0, self.getLog())
        self.assertEqual(len(decoded) % FRAME_SIZE, 0, self.getLog())
        return decoded

    def test_media_filename_placeholders(self):
        self.openTestVideoFile(self.createVideo(name="tmpl_media_src.mkv"))
        self.encodeClip(0, 1, options=_avc_options("%F_static"))
        self.assertValidClip(self.tempdir / "tmpl_media_src_static.mp4")
        self.encodeClip(0, 1, options=_avc_options("%f_static"))
        # %f keeps the source extension, then the output extension is added.
        self.assertValidClip(self.tempdir / "tmpl_media_src.mkv_static.mp4")
        # Templates were expanded, not left literal.
        self.assertFalse((self.tempdir / "%F_static.mp4").exists())
        self.assertFalse((self.tempdir / "%f_static.mp4").exists())

    def test_media_title_placeholder(self):
        source = self.tempdir / "titled_src.mkv"
        self.runTool(
            "ffmpeg", "-v", "error",
            "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=10:duration=3",
            "-c:v", "ffv1",
            "-metadata", "title=My Test Title",
            str(source),
        )
        self.openTestVideoFile(source)
        self.encodeClip(0, 1, options=_avc_options("%T"))
        self.assertValidClip(self.tempdir / "My Test Title.mp4")
        self.assertFalse((self.tempdir / "%T.mp4").exists())

    def test_timestamp_placeholders_with_and_without_ms(self):
        self.openTestVideoFile(self.createVideo(name="tmpl_time_src.mkv"))
        self.encodeClip(0.25, 1.75, options=_avc_options("%F_[%s-%e]"))
        self.assertValidClip(self.tempdir / "tmpl_time_src_[00.00.250-00.01.750].mp4")
        self.encodeClip(0.25, 1.75, options=_avc_options("%F_[%S-%E]"))
        self.assertValidClip(self.tempdir / "tmpl_time_src_[00.00-00.01].mp4")

    def test_property_expansion_fallback_and_conditional(self):
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options=_avc_options("raw_%{=filename/no-ext}"))
        self.assertValidClip(self.tempdir / "raw_source.mp4")
        self.encodeClip(0, 1, options=_avc_options("omit_%{?__no_such_xyz123:hidden}%{!filename:hidden}"))
        self.assertValidClip(self.tempdir / "omit_.mp4")
        self.encodeClip(0, 1, options=_avc_options("prop_%{__no_such_xyz123:fallback123}"))
        self.assertValidClip(self.tempdir / "prop_fallback123.mp4")
        self.encodeClip(0, 1, options=_avc_options("cond_%{?filename:hasfile}"))
        self.assertValidClip(self.tempdir / "cond_hasfile.mp4")
        self.encodeClip(0, 1, options=_avc_options("neg_%{!__no_such_xyz123:shown}"))
        self.assertValidClip(self.tempdir / "neg_shown.mp4")

    def test_literal_percent_and_escaped_counter(self):
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options=_avc_options("pct_%%_end"))
        self.assertValidClip(self.tempdir / "pct_%_end.mp4")
        self.assertFalse((self.tempdir / "pct_%%_end.mp4").exists())
        self.encodeClip(0, 1, options=_avc_options("lit_%%n"))
        # %%n is an escaped literal, not a sequence counter.
        self.assertValidClip(self.tempdir / "lit_%n.mp4")
        self.assertFalse((self.tempdir / "lit_1.mp4").exists())
        self.assertFalse((self.tempdir / "lit_%%n.mp4").exists())

    def test_escaped_percent_with_real_counter(self):
        self.openTestVideoFile(self.createVideo())
        self.encodeClip(0, 1, options=_avc_options("mix100%%_%04n"))
        first = self.tempdir / "mix100%_0001.mp4"
        self.assertValidClip(first)
        first_bytes = first.read_bytes()
        self.encodeClip(0, 1, options=_avc_options("mix100%%_%04n"))
        second = self.tempdir / "mix100%_0002.mp4"
        self.assertValidClip(second)
        # First output preserved; literal %% did not swallow the counter.
        self.assertEqual(first.read_bytes(), first_bytes)
        self.assertFalse((self.tempdir / "mix100%%_0001.mp4").exists())
