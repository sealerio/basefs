#!/bin/bash
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

# if [ $(systemctl status containerd > /dev/null 2>&1; echo $?) != 0 ]; then
#  tar  -xvzf ../cri/containerd.tar.gz -C /
#  cp -rf ../lib64/lib* /usr/lib64/
#  systemctl enable  containerd.service
#  systemctl restart containerd.service
# fi

rootfs=$(dirname "$(pwd)")
image_dir="$rootfs/images"
dump_config_dir="$rootfs/etc/dump-config.toml"
load_images() {
for image in "$image_dir"/*
do
 if [ -f "${image}" ]
 then
  nerdctl load -i "${image}"
 fi
done
}

# mkdir -p /etc/containerd

sed -i "s/sea.hub/${1:-sea.hub}/g" "$dump_config_dir"
sed -i "s/5000/${2:-5000}/g" "$dump_config_dir"

#add cri sandbox image and sea.hub registry cert path
##sandbox_image = "sea.hub:5000/pause:3.6" custom setup
containerd --config "$dump_config_dir" config dump > /etc/containerd/config.toml

systemctl restart containerd.service
load_images
