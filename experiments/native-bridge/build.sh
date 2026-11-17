#!/bin/zsh
set -eu
experiment_dir="${0:A:h}"
project_dir="${experiment_dir:h:h}"
out="${experiment_dir}/build.noindex"
mkdir -p "${out}"
common=(-fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0 -I "${project_dir}/Sources" -framework Foundation -framework CoreAudio -framework CoreGraphics -framework IOKit)
sources=("${project_dir}/Sources/NativeBrightnessBridge.m" "${project_dir}/Sources/NativeProxyAudio.m" "${project_dir}/Sources/NativeBrightness.m" "${project_dir}/Sources/DisplayDDC.m")
clang "${common[@]}" -O2 -arch arm64 -arch x86_64 "${sources[@]}" "${experiment_dir}/NativeBridgeTool.m" -o "${out}/native-bridge"
codesign --force --sign - --identifier local.devicebridge.native-bridge-probe "${out}/native-bridge"
clang "${common[@]}" -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer "${sources[@]}" "${project_dir}/tests/NativeBridgeTests.m" -o "${out}/native-bridge-tests"
"${out}/native-bridge-tests"
"${out}/native-bridge" status > "${out}/status.json"
printf '%s\n' "Built native bridge probes; no driver installed and no audio route changed."
