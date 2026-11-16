#!/bin/zsh
# Builds a release without leaving searchable staging .app bundles behind.
set -eu
project_dir="${0:A:h}"
output_dir="${1:-${project_dir}/release}"
mkdir -p "${output_dir}" "${project_dir}/release.noindex"
output_dir="${output_dir:A}"
"${project_dir}/build.sh" "${project_dir}/build.noindex"
bundle_dir="${project_dir}/build.noindex/BatteryBridge.app"
"${project_dir}/package-verified.sh" "${bundle_dir}" "${output_dir}"
