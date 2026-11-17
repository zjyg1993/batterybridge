#!/bin/zsh
set -eu
project_dir="${0:A:h:h:h}"
source_dir="${project_dir}/Sources/ThirdParty/ProxyAudioDevice"
bundle="${1:?driver bundle path}"
mkdir -p "${bundle}/Contents/MacOS" "${bundle}/Contents/Resources/English.lproj"
clang++ -std=c++14 -fblocks -O2 -DDEBUG=0 -Wno-deprecated-declarations \
  -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -bundle \
  -I "${source_dir}/proxyAudioDevice" -I "${source_dir}/shared" -I "${source_dir}/proxyAudioDevice/PublicUtility" \
  "${source_dir}/proxyAudioDevice/ProxyAudioDevice.cpp" \
  "${source_dir}/proxyAudioDevice/AudioRingBuffer.cpp" \
  "${source_dir}/proxyAudioDevice/utilities.cpp" \
  "${source_dir}/shared/AudioDevice.cpp" \
  "${source_dir}/proxyAudioDevice/PublicUtility/"*.cpp \
  -framework CoreFoundation -framework CoreAudio -framework Carbon -framework AppKit -framework IOKit \
  -o "${bundle}/Contents/MacOS/ProxyAudioDevice"
python3 - "${source_dir}" "${bundle}" <<'PY'
import plistlib,sys
from pathlib import Path
src,out=map(Path,sys.argv[1:])
p=plistlib.loads((src/'proxyAudioDevice/Info.plist').read_bytes())
p.update(CFBundleExecutable='ProxyAudioDevice',CFBundleIdentifier='net.briankendall.ProxyAudioDevice',CFBundleName='ProxyAudioDevice',CFBundleShortVersionString='1.1.0.1',CFBundleVersion='1.1.0.1')
(out/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
PY
cp "${source_dir}/proxyAudioDevice/English.lproj/Localizable.strings" "${bundle}/Contents/Resources/English.lproj/"
cp "${source_dir}/proxyAudioDevice/DeviceIcon.icns" "${bundle}/Contents/Resources/"
cp "${source_dir}/LICENSE" "${bundle}/Contents/Resources/ProxyAudioDevice-LICENSE.txt"
/usr/bin/xattr -dr com.apple.FinderInfo "${bundle}" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "${bundle}" 2>/dev/null || true
codesign --force --sign - "${bundle}"
codesign --verify --strict "${bundle}"
