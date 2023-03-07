#!/bin/bash

# shellcheck disable=SC2046
# shellcheck disable=SC2164
# shellcheck disable=SC2006
# shellcheck disable=SC1091
scripts_path=$(cd `dirname "$0"`; pwd)
#source "${scripts_path}"/utils.sh

set -x

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

disable_firewalld() {
  lsb_dist=$(get_distribution)
  lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
  case "$lsb_dist" in
  ubuntu | deepin | debian | raspbian)
    command -v ufw &>/dev/null && ufw disable
    ;;
  centos | rhel | ol | sles | kylin | neokylin | rocky)
    systemctl stop firewalld && systemctl disable firewalld
    ;;
  *)
    systemctl stop firewalld && systemctl disable firewalld
    echo "unknown system, use default to stop firewalld"
    ;;
  esac
}

copy_bins() {
  chmod -R 755 "${scripts_path}"/../bin/*
  chmod 644 "${scripts_path}"/../bin
  cp "${scripts_path}"/../bin/* /usr/bin
  cp "${scripts_path}"/../scripts/kubelet-pre-start.sh /usr/bin
  chmod +x /usr/bin/kubelet-pre-start.sh
}

copy_kubelet_service(){
  mkdir -p /etc/systemd/system
  cp "${scripts_path}"/../etc/kubelet.service /etc/systemd/system/
  [ -d /etc/systemd/system/kubelet.service.d ] || mkdir /etc/systemd/system/kubelet.service.d
  cp "${scripts_path}"/../etc/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/
}

disable_firewalld
copy_bins
copy_kubelet_service
[ -d /var/lib/kubelet ] || mkdir -p /var/lib/kubelet/
/usr/bin/kubelet-pre-start.sh
systemctl daemon-reload && systemctl enable kubelet

# nvidia-docker.sh need set kubelet labels, it should be run after kubelet
#bash "${scripts_path}"/nvidia-docker.sh || exit 1