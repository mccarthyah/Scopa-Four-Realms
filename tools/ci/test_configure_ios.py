#!/usr/bin/env python3
"""Regression checks for the temporary iOS export configuration."""
import os
import shutil
import subprocess
import tempfile
import unittest
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

    def test_missing_icon_fails_before_modifying_preset(self):
        before = (self.work / 'export_presets.cfg').read_bytes()
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('iOS app icon is missing', result.stderr)
        self.assertEqual((self.work / 'export_presets.cfg').read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
