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
get_distribution() {
  lsb_dist=""
  # Every system that we officially support has /etc/os-release
  if [ -r /etc/os-release ]; then
    lsb_dist="$(. /etc/os-release && echo "$ID")"
  fi
  # Returning an empty string here should be alright since the
  # case statements don't act unless you provide an actual value
  echo "$lsb_dist"
}
disable_selinux() {
  if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
  fi
}
server_load_images() {
  for image in "$image_dir"/*; do
    if [ -f "${image}" ]; then
      ${1} load -i "${image}"
    fi
  done
}

##cri is docker
if [[ $(ls ../cri/docker*.tar.gz) ]]; then
  if ! command_exists docker; then
    lsb_dist=$(get_distribution)
    lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
    echo "current system is $lsb_dist"
    case "$lsb_dist" in
    ubuntu | deepin | debian | raspbian)
      cp ../etc/docker.service /lib/systemd/system/docker.service
      ;;
    centos | rhel | ol | sles | kylin | neokylin)
      cp ../etc/docker.service /usr/lib/systemd/system/docker.service
      ;;
    alios)
      ip link add name docker0 type bridge
      ip addr add dev docker0 172.17.0.1/16
      cp ../etc/docker.service /usr/lib/systemd/system/docker.service
      ;;
    *)
      echo "unknown system to use /lib/systemd/system/docker.service"
      cp ../etc/docker.service /lib/systemd/system/docker.service
      ;;
    esac

    [ -d /etc/docker/ ] || mkdir /etc/docker/ -p

    chmod -R 755 ../cri
    tar -zxvf ../cri/docker*.tar.gz -C /usr/bin
    chmod a+x /usr/bin
    chmod a+x /usr/bin/docker
    chmod a+x /usr/bin/dockerd
    systemctl enable docker.service
    systemctl restart docker.service
    cp ../etc/daemon.json /etc/docker
    if [[ -n $2 && -n $3 ]]; then
      sed -i "s/sea.hub:5000/$2:$3/g" /etc/docker/daemon.json
    fi
  fi
  disable_selinux
  systemctl daemon-reload
  systemctl enable docker.service
  systemctl restart docker.service
  load_image_server="docker"
else
  if ! command_exists containerd; then
    tar zxvf ../cri/cri-*.tar.gz -C /
    cd "$lib_dir" && source install_libseccomp.sh
  fi
  systemctl daemon-reload
  systemctl enable containerd.service
  systemctl restart containerd.service

  sed -i "s/sea.hub/${2:-sea.hub}/g" "$dump_config_dir"
  sed -i "s/5000/${3:-5000}/g" "$dump_config_dir"

  #add cri sandbox image and sea.hub registry cert path
  ##sandbox_image = "sea.hub:5000/pause:3.6" custom setup
  mkdir -p /etc/containerd
  containerd --config "$dump_config_dir" config dump >/etc/containerd/config.toml
  systemctl restart containerd.service
  load_image_server="nerdctl"
fi

server_load_images "${load_image_server}"
