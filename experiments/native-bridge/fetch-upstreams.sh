#!/bin/zsh
# Source acquisition only. Does not install, build or execute third-party code.
set -eu
experiment_dir="${0:A:h}"
upstream_dir="${experiment_dir}/upstreams.noindex"
mkdir -p "${upstream_dir}"
for project in proxy-audio-device candela; do
  destination="${upstream_dir}/${project}"
  [[ ! -e "${destination}" ]] || { print -u2 "Refusing to overwrite ${destination}"; exit 1; }
  if [[ "${project}" == proxy-audio-device ]]; then
    git clone --depth 1 https://github.com/briankendall/proxy-audio-device.git "${destination}"
  else
    git clone --depth 1 https://codeberg.org/livoni-software/candela.git "${destination}"
  fi
done
python3 "${experiment_dir}/audit-upstreams.py" "${upstream_dir}"
