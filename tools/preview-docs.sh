#!/bin/zsh
# Builds an isolated GUI preview using production views and explicit demo data.
# Launch the returned app with Finder; its app menu can open the production menu.
set -eu
project_dir="${0:A:h:h}"
bundle_dir="${project_dir}/build.noindex/DocumentationPreview.app"
mkdir -p "${bundle_dir}/Contents/MacOS"
clang -fobjc-arc -fblocks -Wno-unused-parameter -mmacosx-version-min=13.0 \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework CoreAudio -framework ApplicationServices \
  "${project_dir}/tools/DocumentationPreview.m" "${project_dir}/Sources/Protocol.m" "${project_dir}/Sources/Policy.m" "${project_dir}/Sources/Display.m" "${project_dir}/Sources/DisplayDDC.m" \
  -o "${bundle_dir}/Contents/MacOS/DocumentationPreview"
python3 - "${bundle_dir}/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'CFBundleIdentifier':'local.devicebridge.documentation','CFBundleName':'DeviceBridge Documentation','CFBundleDisplayName':'DeviceBridge Documentation','CFBundleExecutable':'DocumentationPreview','CFBundlePackageType':'APPL','LSUIElement':True,'NSHighResolutionCapable':True}, f)
PY
codesign --force --sign - "${bundle_dir}"
printf '%s\n' "Preview: ${bundle_dir}"
