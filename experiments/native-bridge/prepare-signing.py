#!/usr/bin/env python3
"""Check the supplied Apple profile before adding a restricted HID entitlement."""
import datetime, plistlib, sys
from pathlib import Path
profile = plistlib.loads(Path(sys.argv[1]).read_bytes())
entitlements = profile.get('Entitlements', {})
if entitlements.get('com.apple.developer.hid.virtual.device') is not True:
    raise SystemExit('The Apple provisioning profile does not authorize virtual HID devices')
expiry = profile.get('ExpirationDate')
if not expiry or expiry.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
    raise SystemExit('The Apple provisioning profile is expired')
app_key = 'com.apple.application-identifier' if 'com.apple.application-identifier' in entitlements else 'application-identifier'
app_id = entitlements.get(app_key, '')
if not app_id.endswith('.local.batterybridge.agent'):
    raise SystemExit('The profile must explicitly authorize local.batterybridge.agent')
result = {'com.apple.developer.hid.virtual.device': True, app_key: app_id}
if 'com.apple.developer.team-identifier' in entitlements:
    result['com.apple.developer.team-identifier'] = entitlements['com.apple.developer.team-identifier']
Path(sys.argv[2]).write_bytes(plistlib.dumps(result))
