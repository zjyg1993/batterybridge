#!/bin/zsh
set -eu
project_dir="${0:A:h}"
output_dir="${1:-${project_dir}/build.noindex}"
case "${output_dir}/" in
  *.noindex/*) ;;
  *) output_dir="${output_dir}.noindex" ;;
esac
mkdir -p "${output_dir}"
bundle_dir="${output_dir}/DeviceBridge.app"
mkdir -p "${bundle_dir}/Contents/MacOS" "${bundle_dir}/Contents/Resources"
clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter \
  -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework CoreAudio -framework ApplicationServices \
  "${project_dir}/Sources/main.m" "${project_dir}/Sources/Protocol.m" "${project_dir}/Sources/Policy.m" "${project_dir}/Sources/Display.m" "${project_dir}/Sources/DisplayDDC.m" \
  -o "${bundle_dir}/Contents/MacOS/DeviceBridge"
python3 - "${bundle_dir}/Contents/Info.plist" <<'PY'
import plistlib,sys
p={'CFBundleIdentifier':'local.batterybridge.agent','CFBundleName':'DeviceBridge','CFBundleDisplayName':'DeviceBridge','CFBundleExecutable':'DeviceBridge','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.8.2','CFBundleVersion':'22','LSMinimumSystemVersion':'13.0','LSUIElement':True,'CFBundleIconFile':'AppIcon','NSHighResolutionCapable':True,'NSHumanReadableCopyright':'DeviceBridge · local utility · preview'}
with open(sys.argv[1],'wb') as f:plistlib.dump(p,f)
PY
icon_work="${output_dir}/icon-work"
mkdir -p "${icon_work}/AppIcon.iconset"
clang -fobjc-arc -framework Cocoa "${project_dir}/Sources/Icon.m" -o "${icon_work}/draw-icon"
"${icon_work}/draw-icon" "${icon_work}"
for icon_size in 16 32 128 256 512; do
  cp "${icon_work}/size${icon_size}.png" "${icon_work}/AppIcon.iconset/icon_${icon_size}x${icon_size}.png"
  retina_size=$((icon_size*2))
  cp "${icon_work}/size${retina_size}.png" "${icon_work}/AppIcon.iconset/icon_${icon_size}x${icon_size}@2x.png"
done
python3 - "${icon_work}" "${bundle_dir}/Contents/Resources/AppIcon.icns" <<'PYICON'
import struct,sys,pathlib
src=pathlib.Path(sys.argv[1]); chunks=[]
for typ,size in [('ic07',128),('ic08',256),('ic09',512),('ic10',1024)]:
 data=(src/f'size{size}.png').read_bytes();chunks.append(typ.encode()+struct.pack('>I',len(data)+8)+data)
body=b''.join(chunks);pathlib.Path(sys.argv[2]).write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
PYICON
codesign --force --sign - --identifier local.batterybridge.agent "${bundle_dir}"
codesign --verify --strict --verbose=2 "${bundle_dir}"
clang -fobjc-arc -framework Foundation -I "${project_dir}/Sources" \
 "${project_dir}/Sources/Protocol.m" "${project_dir}/tests/ProtocolTests.m" -o "${output_dir}/protocol-tests"
"${output_dir}/protocol-tests"
printf '%s\n' "Built: ${bundle_dir}"

clang -fobjc-arc -framework Foundation -I "${project_dir}/Sources" "${project_dir}/Sources/Policy.m" "${project_dir}/tests/PolicyTests.m" -o "${output_dir}/policy-tests"
"${output_dir}/policy-tests"
clang -fobjc-arc -fblocks -Wno-unused-parameter -mmacosx-version-min=13.0 \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework CoreAudio -framework ApplicationServices \
  "${project_dir}/tests/InterfaceTests.m" "${project_dir}/Sources/Protocol.m" "${project_dir}/Sources/Policy.m" "${project_dir}/Sources/Display.m" "${project_dir}/Sources/DisplayDDC.m" \
  -o "${output_dir}/interface-tests"
"${output_dir}/interface-tests"

clang -fobjc-arc -framework Foundation -I "${project_dir}/Sources" \
  "${project_dir}/Sources/DisplayDDC.m" "${project_dir}/tests/DisplayTests.m" -o "${output_dir}/display-tests"
"${output_dir}/display-tests"
clang -fobjc-arc -fblocks -mmacosx-version-min=13.0 -framework Cocoa -framework IOKit -framework CoreAudio -framework ApplicationServices -I "${project_dir}/Sources" \
  "${project_dir}/Sources/Display.m" "${project_dir}/Sources/DisplayDDC.m" "${project_dir}/tests/DisplayControllerTests.m" -o "${output_dir}/display-controller-tests"
"${output_dir}/display-controller-tests"
