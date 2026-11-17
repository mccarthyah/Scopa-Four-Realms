#!/usr/bin/env python3
"""Check toolchain guards without invoking Xcode or building an app."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

CHECK = Path(__file__).with_name('check_apple_toolchain.sh')


class AppleToolchainTest(unittest.TestCase):
    def check_versions(self, xcode, sdk):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            (work / 'xcodebuild').write_text('#!/bin/sh\nprintf "Xcode %s\\nBuild version 27A000\\n" "$MOCK_XCODE"\n')
            (work / 'xcrun').write_text('#!/bin/sh\nprintf "%s\\n" "$MOCK_SDK"\n')
            for command in ('xcodebuild', 'xcrun'):
                (work / command).chmod(0o755)
            env = dict(os.environ, PATH=f'{temp}{os.pathsep}{os.environ["PATH"]}',
                       MOCK_XCODE=xcode, MOCK_SDK=sdk)
            return subprocess.run(['bash', str(CHECK)], env=env, text=True, capture_output=True)

    def test_supported_xcode_and_sdk(self):
        for xcode, sdk in [('27.0', '27.0'), ('27.2', '27.1'), ('28.0', '28.0')]:
            with self.subTest(xcode=xcode, sdk=sdk):
                self.assertEqual(self.check_versions(xcode, sdk).returncode, 0)

    def test_old_toolchains_are_rejected(self):
        for xcode, sdk in [('26.6', '27.0'), ('27.0', '26.5')]:
            with self.subTest(xcode=xcode, sdk=sdk):
                result = self.check_versions(xcode, sdk)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('too old', result.stderr)

    def test_invalid_versions_are_rejected(self):
        for xcode, sdk in [('', '27.0'), ('27.0', ''), ('27.0', 'beta')]:
            with self.subTest(xcode=xcode, sdk=sdk):
                self.assertNotEqual(self.check_versions(xcode, sdk).returncode, 0)


if __name__ == '__main__':
    unittest.main()
