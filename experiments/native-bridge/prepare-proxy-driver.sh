#!/bin/zsh
# Prepare a private copy; never alter the installed App or re-sign extracted code.
set -eu
archive="${1:?driver archive}"
stage="${2:?empty staging directory}"
[[ -f "${archive}" && -d "${stage}" && ! -e "${stage}/ProxyAudioDevice.driver" ]] || exit 1
/usr/bin/ditto -x -k "${archive}" "${stage}"
bundle="${stage}/ProxyAudioDevice.driver"
[[ -d "${bundle}" && ! -L "${bundle}" ]] || exit 1
# Finder can add these attributes when inspecting/copying bundles. They are not
# signed payload. Remove only those two attributes, then verify original signing.
/usr/bin/xattr -dr com.apple.FinderInfo "${bundle}" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "${bundle}" 2>/dev/null || true
/usr/bin/codesign --verify --strict "${bundle}"
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${bundle}/Contents/Info.plist")
[[ "${identifier}" == net.briankendall.ProxyAudioDevice ]] || exit 1
