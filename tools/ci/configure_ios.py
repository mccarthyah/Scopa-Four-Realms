#!/usr/bin/env python3
"""Configure a temporary Godot iOS export preset for a CI run (not for commit)."""
import os
import re
from pathlib import Path


def required(name):
    value = os.environ.get(name, '').strip()
    if not value:
        raise ValueError(f'{name} is required; see docs/TESTFLIGHT.md')
    return value


def main():
    team = required('APPLE_TEAM_ID')
    bundle = required('IOS_BUNDLE_ID')
    version = os.environ.get('IOS_VERSION', '1.0').strip() or '1.0'
    build = required('IOS_BUILD_NUMBER')
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('APPLE_TEAM_ID must be the 10-character Apple Developer team ID')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle):
        raise ValueError('IOS_BUNDLE_ID must be a valid reverse-DNS bundle ID')
    if not re.fullmatch(r'\d+(?:\.\d+){1,2}', version):
        raise ValueError('IOS_VERSION must have two or three numeric components, e.g. 1.0')
    if not re.fullmatch(r'[1-9][0-9]{0,17}', build):
        raise ValueError('IOS_BUILD_NUMBER must be a positive integer (up to 18 digits)')
    icon = Path('assets/icon/four-realms-iphone-icon.png')
    if not icon.is_file():
        raise ValueError(f'iOS app icon is missing: {icon}')
    path = Path('export_presets.cfg')
    text = path.read_text()
    start = text.index('[preset.2.options]')
    end = text.index('\n[preset.3]', start)
    section = text[start:end]
    replacements = {
        'application/app_store_team_id': f'"{team}"',
        'application/bundle_identifier': f'"{bundle}"',
        'application/short_version': f'"{version}"',
        'application/version': f'"{build}"',
        'application/export_project_only': 'true',
        'icons/icon_1024x1024': f'"res://{icon.as_posix()}"',
    }
    for key, value in replacements.items():
        pattern = r'^' + re.escape(key) + r'=.*$'
        if re.search(pattern, section, flags=re.M):
            section = re.sub(pattern, lambda _: key + '=' + value, section, count=1, flags=re.M)
        else:
            section = section.rstrip() + '\n' + key + '=' + value + '\n'
    path.write_text(text[:start] + section + text[end:])
    print(f'Configured iOS export: {bundle}, version {version}, build {build}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as exc:
        raise SystemExit(str(exc))
