"""Exercise the real GIF command modifier and inspect decoded subtitle pixels."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(all(shutil.which(tool) for tool in ('mpv', 'ffmpeg', 'moonc', 'lua')),
                     'requires mpv, ffmpeg, MoonScript and Lua')
class TestGifSubtitles(unittest.TestCase):
    def run_tool(self, *args):
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace") +
                         result.stdout.decode(errors="replace"))
        return result.stdout

    def test_subtitles_before_palette(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix='mpv-webm-gif-') as directory:
            tmp = Path(directory)
            # Compile the production modifier with its real utility functions.
            source = 'local mp, options\n' + '\n'.join((root / name).read_text() for name in
                               ('src/util.moon', 'src/formats/base.moon', 'src/formats/gif.moon'))
            source += r"""
mp = {get_property: -> "no"}
options = {gif_dither: tonumber(arg[1])}
command = [arg[i] for i = 2, #arg]
for value in *formats.gif\postCommandModifier(command, nil, 1, 2)
    io.write(value, "\0")
"""
            moon = tmp / 'command.moon'
            lua = tmp / 'command.lua'
            moon.write_text(source)
            self.run_tool('moonc', '-o', str(lua), str(moon))
            srt = tmp / 'caption.srt'
            srt.write_text('1\n00:00:00,500 --> 00:00:02,500\nSUBTITLE TEST\n')
            ass = tmp / 'caption.ass'
            self.run_tool('ffmpeg', '-v', 'error', '-i', str(srt), str(ass))
            for subtitle in (srt, ass):
                video = tmp / (subtitle.suffix[1:] + '.mkv')
                self.run_tool('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
                              'color=c=blue:s=320x180:r=10:d=3', '-i', str(subtitle),
                              '-c:v', 'ffv1', '-c:s', subtitle.suffix[1:], str(video))
                for dither in (2, 6):
                    with self.subTest(subtitle=subtitle.suffix, dither=dither):
                        decoded = {}
                        for sid in ('no', '1', 'hidden'):
                            output = tmp / f'{subtitle.suffix}-{dither}-{sid}.gif'
                            command = ['mpv', '--no-config', '--load-scripts=no', '--scripts-clr',
                                       '--sub-scale=3', '--sub-auto=no', str(video),
                                       f'--sid={1 if sid == "hidden" else sid}',
                                       f'--sub-visibility={"no" if sid == "hidden" else "yes"}',
                                       '--no-audio', '--ovc=gif',
                                       f'--o={output}', '--start=1', '--end=2',
                                       '--vf-add=lavfi-scale=160:90', '--vf-add=fps=10']
                            modified = self.run_tool('lua', str(lua), str(dither), *command)
                            self.run_tool(*modified.decode().rstrip('\0').split('\0'))
                            decoded[sid] = self.run_tool('ffmpeg', '-v', 'error', '-i',
                                                        str(output), '-pix_fmt', 'rgb24',
                                                        '-f', 'rawvideo', '-')
                        self.assertTrue(decoded['hidden'] == decoded['no'])
                        frame_size = 160 * 90 * 3
                        self.assertEqual(len(decoded['no']), 10 * frame_size)
                        self.assertEqual(len(decoded['1']), len(decoded['no']))
                        # A middle frame avoids mpv's first-frame subtitle startup delay.
                        off = decoded['no'][5 * frame_size:6 * frame_size]
                        on = decoded['1'][5 * frame_size:6 * frame_size]
                        self.assertTrue(on != off, 'selected subtitles were not burned in')
                        white = lambda data: sum(all(c > 100 for c in data[i:i+3])
                                                 for i in range(0, len(data), 3))
                        self.assertEqual(white(off), 0)
                        self.assertGreater(white(on), 20)
