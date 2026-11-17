#!/bin/zsh
# Invoked after the first-launch prompt and macOS administrator authorization.
set -eu
archive="${1:?source driver archive}"
destination="/Library/Audio/Plug-Ins/HAL/ProxyAudioDevice.driver"
[[ $EUID == 0 ]] || { print -u2 'Administrator authorization required'; exit 1; }
[[ ! -e "${destination}" ]] || { print -u2 'Existing driver preserved'; exit 1; }
/bin/mkdir -p /Library/Audio/Plug-Ins/HAL
stage=$(/usr/bin/mktemp -d /Library/Audio/Plug-Ins/HAL/.devicebridge-install.XXXXXX)
trap '/bin/rm -rf "${stage}"' EXIT
# Extract and clean the private staging copy BEFORE codesign validation.
/bin/zsh "${0:A:h}/prepare-proxy-driver.sh" "${archive}" "${stage}"
/usr/sbin/chown -R root:wheel "${stage}/ProxyAudioDevice.driver"
/bin/chmod -R go-w "${stage}/ProxyAudioDevice.driver"
/usr/bin/codesign --verify --strict "${stage}/ProxyAudioDevice.driver"
/bin/mv "${stage}/ProxyAudioDevice.driver" "${destination}"
/usr/bin/killall coreaudiod || true
