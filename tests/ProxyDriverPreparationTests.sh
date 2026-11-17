#!/bin/zsh
set -eu
driver="${1:?signed driver}"
prepare="${2:?preparation script}"
work=$(mktemp -d "${TMPDIR:-/tmp}/devicebridge-driver-test.XXXXXX")
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/dirty" "${work}/extracted" "${work}/bad-extracted"
ditto "${driver}" "${work}/dirty/ProxyAudioDevice.driver"
# Reproduce Finder pollution on an otherwise valid signed bundle.
xattr -wx com.apple.FinderInfo 0100000000000000000000000000000000000000000000000000000000000000 "${work}/dirty/ProxyAudioDevice.driver"
xattr -w com.apple.ResourceFork regression "${work}/dirty/ProxyAudioDevice.driver/Contents/Info.plist"
if codesign --verify --strict "${work}/dirty/ProxyAudioDevice.driver" 2>/dev/null; then print -u2 'Fixture must reproduce the original signature error'; exit 1; fi
ditto -c -k --keepParent "${work}/dirty/ProxyAudioDevice.driver" "${work}/driver.zip"
/bin/zsh "${prepare}" "${work}/driver.zip" "${work}/extracted"
cmp "${driver}/Contents/MacOS/ProxyAudioDevice" "${work}/extracted/ProxyAudioDevice.driver/Contents/MacOS/ProxyAudioDevice"
xattr -p com.apple.FinderInfo "${work}/dirty/ProxyAudioDevice.driver" >/dev/null
# Cleanup may remove metadata, but must never conceal modified signed contents.
print 'tampered' >> "${work}/dirty/ProxyAudioDevice.driver/Contents/Resources/ProxyAudioDevice-LICENSE.txt"
ditto -c -k --keepParent "${work}/dirty/ProxyAudioDevice.driver" "${work}/bad.zip"
if /bin/zsh "${prepare}" "${work}/bad.zip" "${work}/bad-extracted" 2>/dev/null; then print -u2 'Tampered signed payload was accepted'; exit 1; fi
print 'PASS: Finder metadata regression, original source preserved, tampered payload rejected'
