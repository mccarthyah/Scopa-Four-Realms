#!/usr/bin/env python3
"""Regression checks for the temporary iOS export configuration."""
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ICON = Path('assets/icon/four-realms-iphone-icon.png')


class ConfigureIOSTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.work = Path(self.temp.name)
        shutil.copy(ROOT / 'export_presets.cfg', self.work)
        self.env = dict(os.environ, APPLE_TEAM_ID='ABCDE12345',
                        IOS_BUNDLE_ID='com.example.fourrealms',
                        IOS_VERSION='1.0', IOS_BUILD_NUMBER='123')

    def tearDown(self):
        self.temp.cleanup()

    def configure(self):
        return subprocess.run(['python3', str(ROOT / 'tools/ci/configure_ios.py')],
                              cwd=self.work, env=self.env, text=True, capture_output=True)

    def test_ci_uses_supplied_icon(self):
        (self.work / ICON).parent.mkdir(parents=True)
        shutil.copy(ROOT / ICON, self.work / ICON)
        result = self.configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        preset = (self.work / 'export_presets.cfg').read_text()
        ios = preset.split('[preset.2.options]', 1)[1].split('[preset.3]', 1)[0]
        self.assertEqual(ios.count('icons/icon_1024x1024='), 1)
        self.assertIn(f'icons/icon_1024x1024="res://{ICON.as_posix()}"', ios)
        self.assertNotIn('assets/ios_app_icon.png', ios)

    def test_ios_storyboard_uses_transparent_image_in_both_scales(self):
        # Godot's iOS exporter otherwise uses boot_splash/image even when the
        # engine's boot splash image is disabled, showing the logo twice.
        preset = (ROOT / 'export_presets.cfg').read_text()
        ios = preset.split('[preset.2.options]', 1)[1].split('[preset.3]', 1)[0]
        launch_path = 'res://assets/branding/ios_launch_transparent.png'
        for scale in ('2x', '3x'):
            self.assertIn(f'storyboard/custom_image@{scale}="{launch_path}"', ios)
        png = (ROOT / launch_path.removeprefix('res://')).read_bytes()
        self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(struct.unpack('>IIBBBBB', png[16:29]), (1, 1, 8, 6, 0, 0, 0))
        chunks = []
        pos = 8
        while pos < len(png):
            size = struct.unpack('>I', png[pos:pos + 4])[0]
            kind = png[pos + 4:pos + 8]
            if kind == b'IDAT':
                chunks.append(png[pos + 8:pos + 8 + size])
            pos += size + 12
        self.assertEqual(zlib.decompress(b''.join(chunks)), b'\0\0\0\0\0')

    def test_missing_icon_fails_before_modifying_preset(self):
        before = (self.work / 'export_presets.cfg').read_bytes()
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('iOS app icon is missing', result.stderr)
        self.assertEqual((self.work / 'export_presets.cfg').read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
