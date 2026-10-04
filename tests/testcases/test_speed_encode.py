import struct

from .base_test_case import BaseTestCase


class TestSpeedEncode(BaseTestCase):
    """Encoding at a non-default playback speed must keep the selected range."""

    # --- video -----------------------------------------------------------------

    def makeColorSource(self):
        # Green everywhere except a red band covering source seconds 2..3.
        return self.createVideo(
            name="speed_color.mkv", size="64x64", duration=5, color="green",
            filters="drawbox=x=0:y=0:w=iw:h=ih:color=red:t=fill:"
                    "enable='between(t,2,3)'",
        )

    def averageColor(self, path):
        data = self.decodeVideo(path)
        pixels = len(data) // 3
        self.assertGreater(pixels, 0)
        return (
            sum(data[0::3]) / pixels,
            sum(data[1::3]) / pixels,
            sum(data[2::3]) / pixels,
        )

    def test_video_segment_survives_speed_change(self):
        self.openTestVideoFile(self.makeColorSource())
        for speed in (1, 0.5, 2):
            self.setProperty("speed", speed)
            self.encodeClip(2, 3, options={
                "output_format": "avc",
                "output_template": f"video_{speed}",
            })
            out = self.tempdir / f"video_{speed}.mp4"
            duration = float(self.probeVideo(out)["format"]["duration"])
            # Source range 2..3 (1s) is stretched by 1/speed.
            self.assertAlmostEqual(duration, 1 / speed, delta=0.2)
            red, green, _ = self.averageColor(out)
            self.assertGreater(red, 180, f"speed={speed}: expected red segment")
            self.assertLess(green, 80, f"speed={speed}: expected red segment")

    # --- audio -----------------------------------------------------------------

    def makeAudioSource(self):
        # 500 Hz tone only during source seconds 2..3, silence elsewhere.
        return self.createVideo(
            name="speed_audio.mkv", color="black", duration=5,
            audio="aevalsrc=sin(2*PI*500*t)*between(t\\,2\\,3):s=48000:d=5",
        )

    def audioLevel(self, path):
        data = self.runTool("ffmpeg", "-v", "error", "-i", str(path),
                            "-ac", "1", "-ar", "48000", "-f", "s16le", "-")
        count = len(data) // 2
        samples = struct.unpack(f"<{count}h", data[:count * 2])
        return sum(abs(s) for s in samples) / count

    def test_audio_segment_survives_speed_change(self):
        self.openTestVideoFile(self.makeAudioSource())
        for speed in (0.5, 2):
            self.setProperty("speed", speed)
            self.encodeClip(2, 3, options={
                "output_format": "mp3",
                "output_template": f"audio_{speed}",
            })
            out = self.tempdir / f"audio_{speed}.mp3"
            duration = float(self.probeVideo(out)["format"]["duration"])
            self.assertAlmostEqual(duration, 1 / speed, delta=0.2)
            self.assertGreater(self.audioLevel(out), 1000, f"speed={speed}: silent audio")
        # Control: encoding the silent range must stay silent.
        self.setProperty("speed", 1)
        self.encodeClip(0, 1, options={
            "output_format": "mp3",
            "output_template": "audio_silent",
        })
        self.assertLess(self.audioLevel(self.tempdir / "audio_silent.mp3"), 100)

    def test_speed_change_preserves_delayed_audio_onset(self):
        # Audio starts at source second 3, one second after the selection starts.
        # Independent STARTPTS resets incorrectly move that tone to file time 0.
        source = self.tempdir / "delayed_audio.mkv"
        self.runTool("ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                     "color=c=black:s=64x64:r=20:d=5", "-itsoffset", "3",
                     "-f", "lavfi", "-i", "sine=frequency=500:sample_rate=48000:duration=2",
                     "-c:v", "ffv1", "-c:a", "pcm_s16le", str(source))
        self.openTestVideoFile(source)
        for speed in (1, 0.5, 2):
            with self.subTest(speed=speed):
                self.setProperty("speed", speed)
                name = f"delayed_audio_{speed}"
                self.encodeClip(2, 4, options={
                    "output_format": "avc", "output_template": name, "twopass": False,
                })
                out = self.tempdir / f"{name}.mp4"
                streams = self.probeVideo(out)["streams"]
                audio = next(s for s in streams if s["codec_type"] == "audio")
                video = next(s for s in streams if s["codec_type"] == "video")
                data = self.runTool("ffmpeg", "-v", "error", "-i", str(out),
                                    "-map", "0:a:0", "-ac", "1", "-ar", "48000",
                                    "-f", "s16le", "-")
                count = len(data) // 2
                samples = struct.unpack(f"<{count}h", data[:count * 2])
                # Locate actual signal as well as the stream timestamp, so codec
                # priming or leading silence cannot masquerade as an A/V offset.
                onset = None
                for i in range(0, count, 240):
                    window = samples[i:i + 240]
                    if sum(abs(s) for s in window) / len(window) > 500:
                        onset = i / 48000
                        break
                self.assertIsNotNone(onset, "delayed audio tone was not encoded")
                onset += float(audio["start_time"]) - float(video["start_time"])
                self.assertAlmostEqual(onset, 1 / speed, delta=0.08,
                                       msg=f"speed={speed}: source A/V offset was lost")

    # --- subtitles -------------------------------------------------------------

    def makeSubbedSource(self, filters=None):
        plain = self.createVideo(name="sub_plain.mkv", color="black", duration=5,
                                 filters=filters)
        srt = self.tempdir / "caption.srt"
        srt.write_text("1\n00:00:02,500 --> 00:00:02,900\nTEST SUB\n")
        source = self.tempdir / "subbed.mkv"
        self.runTool("ffmpeg", "-v", "error", "-i", str(plain), "-i", str(srt),
                     "-map", "0:v", "-map", "1:0", "-c:v", "copy", "-c:s", "srt", str(source))
        return source

    def brightFrameTimes(self, path):
        # FFprobe 4.4 does not expose frame=pts_time. This decoded-frame field
        # is available in both the pinned environment and current FFmpeg.
        out = self.runTool("ffprobe", "-v", "error", "-select_streams", "v:0",
                           "-show_entries", "frame=best_effort_timestamp_time",
                           "-of", "csv=p=0", str(path))
        pts = [float(t.strip(",")) for t in out.decode().split()]
        # Keep one decoded frame per reported PTS, including variable-rate GIFs.
        data = self.runTool("ffmpeg", "-v", "error", "-i", str(path), "-vsync", "0",
                            "-pix_fmt", "rgb24", "-f", "rawvideo", "-")
        frames = len(pts)
        self.assertGreater(frames, 0, "ffprobe returned no video frame timestamps")
        frame_size = len(data) // frames
        times = []
        for i in range(frames):
            frame = data[i * frame_size:(i + 1) * frame_size]
            bright = sum(1 for j in range(0, len(frame), 3)
                         if frame[j] > 100 and frame[j + 1] > 100 and frame[j + 2] > 100)
            if bright > 5:
                times.append(pts[i])
        return times

    def test_subtitle_timing_survives_speed_change(self):
        self.openTestVideoFile(self.makeSubbedSource())
        self.setProperty("sub-scale", 3)
        self.setProperty("sid", 1)
        # Caption at source 2.5..2.9, clip source 2..3, so file time (t-2)/speed.
        for speed, (lo, hi) in ((1, (0.5, 0.9)), (0.5, (1.0, 1.8)), (2, (0.25, 0.45))):
            self.setProperty("speed", speed)
            self.encodeClip(2, 3, options={
                "output_format": "avc",
                "output_template": f"sub_{speed}",
            })
            times = self.brightFrameTimes(self.tempdir / f"sub_{speed}.mp4")
            self.assertTrue(times, f"speed={speed}: subtitle was not burned in")
            self.assertGreaterEqual(min(times), lo - 0.15, f"speed={speed}: subtitle too early")
            self.assertLessEqual(max(times), hi + 0.15, f"speed={speed}: subtitle too late")

    def test_speed_change_scales_existing_subtitle_delay(self):
        self.openTestVideoFile(self.makeSubbedSource(filters="fps=20"))
        self.setProperty("sub-scale", 3)
        self.setProperty("sid", 1)
        self.setProperty("sub-speed", 1.1)
        for speed in (1, 0.5, 2):
            for delay in (-0.4, 0.4):
                with self.subTest(speed=speed, delay=delay):
                    self.setProperty("speed", speed)
                    self.setProperty("sub-delay", delay)
                    name = f"sub_delay_{speed}_{delay}"
                    self.encodeClip(2, 4, options={
                        "output_format": "avc", "output_template": name, "twopass": False,
                    })
                    times = self.brightFrameTimes(self.tempdir / f"{name}.mp4")
                    self.assertTrue(times, "adjusted subtitle was not burned in")
                    # Apply the user's source-domain adjustments before scaling
                    # the caption's position relative to the shared clip origin.
                    expected = (2.5 * 1.1 + delay - 2) / speed
                    self.assertAlmostEqual(min(times), expected, delta=0.075 / speed,
                                           msg="existing subtitle delay was not scaled")

    def test_gif_subtitle_timing_survives_speed_change(self):
        self.openTestVideoFile(self.makeSubbedSource(filters="fps=20"))
        self.setProperty("sub-scale", 3)
        self.setProperty("sid", 1)
        for speed in (1, 0.5, 2):
            for sub_speed, delay in ((1, 0), (1.05, 0.1)):
                with self.subTest(speed=speed, sub_speed=sub_speed, delay=delay):
                    self.setProperty("speed", speed)
                    self.setProperty("sub-speed", sub_speed)
                    self.setProperty("sub-delay", delay)
                    name = f"gif_sub_{speed}_{sub_speed}_{delay}"
                    self.encodeClip(2, 3, options={
                        "output_format": "gif", "output_template": name, "fps": 20,
                    })
                    times = self.brightFrameTimes(self.tempdir / f"{name}.gif")
                    self.assertTrue(times, "GIF subtitle was not burned in")
                    expected = (2.5 * sub_speed + delay - 2) / speed
                    # Allow source-frame quantization plus GIF frame rounding.
                    self.assertAlmostEqual(min(times), expected,
                                           delta=0.075 / speed + 0.025,
                                           msg="GIF subtitle was retimed before burn-in")
