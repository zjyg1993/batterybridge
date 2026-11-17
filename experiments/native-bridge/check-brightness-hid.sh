#!/bin/zsh
# Standalone ad-hoc diagnostics, not proof of the signed application's ability.
# No display EDID, brightness setting, or persistent device association is changed.
set -eu
experiment_dir="${0:A:h}"
out="${experiment_dir}/build.noindex"
/bin/zsh "${experiment_dir}/build.sh"
"${out}/native-bridge" hid-capability > "${out}/hid-capability.json"
architecture=$(uname -m)
xcrun swiftc -parse-as-library -target "${architecture}-apple-macos15.0" \
  -module-cache-path "${out}/ModuleCache" \
  "${experiment_dir}/CoreHIDCapabilityProbe.swift" -o "${out}/corehid-capability-probe"
codesign --verify --strict "${out}/corehid-capability-probe"
"${out}/corehid-capability-probe" "${out}/hid-capability.json" > "${out}/corehid-capability.json"
python3 - "${out}" <<'PY'
import base64, json, pathlib, sys
out = pathlib.Path(sys.argv[1])
legacy = json.loads((out / 'hid-capability.json').read_text())
modern = json.loads((out / 'corehid-capability.json').read_text())
descriptor = base64.b64decode(legacy['brightnessHIDDescriptorBase64'], validate=True)
assert len(descriptor) == modern['descriptorBytes']
assert legacy['edidModified'] is False and modern['edidModified'] is False
assert legacy['displayBindingVerified'] is False and modern['displayBindingVerified'] is False
print(json.dumps({'IOHID': legacy, 'CoreHID': modern}, indent=2))
print('Diagnostics completed; neither result verifies native display binding or physical brightness.')
PY
