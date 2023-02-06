#!/bin/bash
# shellcheck disable=SC1091
# Copyright © 2021 Alibaba Group Holding Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x
set -e

rootfs=$(dirname "$(pwd)")
image_dir="$rootfs/images"
lib_dir="${rootfs}/lib"
dump_config_dir="$rootfs/etc/dump-config.toml"

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

server_load_images() {
  for image in "$image_dir"/*; do
    if [ -f "${image}" ]; then
      ${1} load -i "${image}"
    fi
  done
}

##cri is containerd
if ! command_exists containerd; then
  tar zxvf ../cri/cri-*.tar.gz -C /
  cd "$lib_dir" && source install_libseccomp.sh
fi
systemctl daemon-reload
systemctl enable containerd.service
systemctl restart containerd.service

sed -i "s/sea.hub/${2:-sea.hub}/g" "$dump_config_dir"
sed -i "s/5000/${3:-5000}/g" "$dump_config_dir"
mkdir -p /etc/containerd
containerd --config "$dump_config_dir" config dump >/etc/containerd/config.toml
systemctl restart containerd.service
load_image_server="nerdctl"

server_load_images "${load_image_server}"
