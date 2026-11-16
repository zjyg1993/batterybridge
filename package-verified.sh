#!/bin/zsh
# Packages an already tested bundle without rebuilding or changing its signature.
set -eu
project_dir="${0:A:h}"
bundle_dir="${1:?Pass the tested BatteryBridge.app path}"
output_dir="${2:-${project_dir}/release}"
bundle_dir="${bundle_dir:A}"
mkdir -p "${output_dir}" "${project_dir}/release.noindex"
output_dir="${output_dir:A}"
codesign --verify --strict --verbose=2 "${bundle_dir}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${bundle_dir}/Contents/Info.plist")
runtime_version=$("${bundle_dir}/Contents/MacOS/BatteryBridge" --version)
[[ "${runtime_version}" == "${version}-preview" ]] || { print -u2 'Bundle and executable versions differ'; exit 1; }
image_path="${output_dir}/BatteryBridge-${version}-preview.dmg"
[[ ! -e "${image_path}" ]] || { print -u2 'Release already exists'; exit 1; }
release_dir=$(mktemp -d "${project_dir}/release.noindex/package.XXXXXX")
trap 'rm -rf "${release_dir}"' EXIT
python3 - "${project_dir}" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1])
readme=(root/'README.md').read_text()
images=re.findall(r'<img\b[^>]*\bsrc=[\x27\x22]([^\x27\x22]+)',readme)
if './docs/assets/logo.png' not in images:
    raise SystemExit('README must reference the packaged project Logo')
for src in images:
    if '://' not in src and not (root/src).is_file():
        raise SystemExit('Missing README image: '+src)
logo=(root/'docs/assets/logo.png').read_bytes()
if not logo.startswith(b'\x89PNG\r\n\x1a\n'):
    raise SystemExit('README Logo is not a valid PNG file')
PY
volume_dir="${release_dir}/volume"
mkdir -p "${volume_dir}/docs/assets"
ditto "${bundle_dir}" "${volume_dir}/BatteryBridge.app"
codesign --verify --strict "${volume_dir}/BatteryBridge.app"
cmp "${bundle_dir}/Contents/MacOS/BatteryBridge" "${volume_dir}/BatteryBridge.app/Contents/MacOS/BatteryBridge"
ln -s /Applications "${volume_dir}/Applications"
touch "${volume_dir}/.metadata_never_index"
cp "${project_dir}/README.md" "${volume_dir}/README.md"
cp "${project_dir}/docs/assets/logo.png" "${volume_dir}/docs/assets/logo.png"
python3 - "${project_dir}" "${volume_dir}/BatteryBridge-Source.zip" <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import sys
root=Path(sys.argv[1])
with ZipFile(sys.argv[2], 'w', ZIP_DEFLATED) as z:
    for name in ['Sources','tests','docs','README.md','AGENTS.md','.gitignore','build.sh','release.sh','package-verified.sh']:
        p=root/name
        for f in sorted(p.rglob('*')) if p.is_dir() else [p]:
            if f.is_file() and f.name!='.DS_Store':z.write(f,Path('BatteryBridge')/f.relative_to(root))
with ZipFile(sys.argv[2]) as z:
    for name in ['README.md','docs/assets/logo.png']:
        if z.read('BatteryBridge/'+name)!=(root/name).read_bytes():
            raise SystemExit('Source archive mismatch: '+name)
PY
hdiutil makehybrid -hfs -hfs-volume-name "BatteryBridge ${version} Preview" -o "${release_dir}/image.hfs" "${volume_dir}"
hdiutil convert "${release_dir}/image.hfs.dmg" -format UDZO -o "${image_path}"
hdiutil verify "${image_path}"
if [[ "${bundle_dir}" == "${project_dir}/build.noindex/BatteryBridge.app" ]]; then rm -rf "${bundle_dir}"; fi
printf '%s\n' "Verified release: ${image_path}"
