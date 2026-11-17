#!/usr/bin/env python3
"""Validate an App Store distribution profile decoded with security cms."""
import datetime
import os
import plistlib
import sys
from pathlib import Path


def main():
    with open(sys.argv[1], 'rb') as f:
        profile = plistlib.load(f)
    team = os.environ['APPLE_TEAM_ID']
    bundle = os.environ['IOS_BUNDLE_ID']
    ent = profile.get('Entitlements', {})
    prefix = profile.get('ApplicationIdentifierPrefix', [])
    if team not in profile.get('TeamIdentifier', []):
        raise ValueError('Provisioning profile does not belong to APPLE_TEAM_ID')
    if not any(ent.get('application-identifier') == p + '.' + bundle for p in prefix):
        raise ValueError('Provisioning profile does not match IOS_BUNDLE_ID (explicit App ID required)')
    if ent.get('get-task-allow', False) or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices'):
        raise ValueError('Use an App Store distribution profile, not development, ad-hoc or enterprise')
    if not ent.get('beta-reports-active', False):
        raise ValueError('Profile is not marked for App Store/TestFlight distribution (beta-reports-active)')
    expiry = profile.get('ExpirationDate')
    if not expiry or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('Provisioning profile is expired or has no expiration date')
    uuid = profile.get('UUID', '')
    if not uuid or any(c not in '0123456789ABCDEFabcdef-' for c in uuid):
        raise ValueError('Provisioning profile UUID is missing or invalid')
    out = {'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
           'teamID': team, 'provisioningProfiles': {bundle: uuid},
           'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True}
    with open(sys.argv[2], 'wb') as f:
        plistlib.dump(out, f)
    with open(os.environ['GITHUB_ENV'], 'a') as f:
        f.write('PROFILE_UUID=' + uuid + '\n')
    print('Verified team, explicit bundle ID, App Store profile and expiration.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, IndexError, plistlib.InvalidFileException) as exc:
        raise SystemExit(str(exc))
