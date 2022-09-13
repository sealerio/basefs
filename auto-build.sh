#!/bin/bash

set -e

for i in "$@"; do
  case $i in
  -c=* | --cri=*)
    cri="${i#*=}"
    if [ "$cri" != "docker" ] && [ "$cri" != "containerd" ]; then
      echo "Unsupported container runtime: ${cri}"
      exit 1
    fi
    shift # past argument=value
    ;;
  -n=* | --buildName=*)
    buildName="${i#*=}"
    shift # past argument=value
    ;;
  --platform=*)
    platform="${i#*=}"
    shift # past argument=value
    ;;
  --push)
    push="true"
    shift # past argument=value
    ;;
  -p=* | --password=*)
    password="${i#*=}"
    shift # past argument=value
    ;;
  -u=* | --username=*)
    username="${i#*=}"
    shift # past argument=value
    ;;
  --k8s-version=*)
    k8s_version="${i#*=}"
    shift # past argument=value
    ;;
  -h | --help)
    echo "
### Options
  --k8s-version         set the kubernetes k8s_version of the Clusterimage, k8s_version must be greater than 1.13
  -c, --cri             cri can be set to docker or containerd between kubernetes 1.20-1.24 versions
  -n, --buildName       set build image name, default is 'registry.cn-qingdao.aliyuncs.com/sealer-io/kubernetes:${k8s_version}'
  --platform            set the build mirror platform, the default is linux/amd64,linux/arm64
  --push                push clusterimage after building the clusterimage. The image name must contain the full name of the repository, and use -u and -p to specify the username and password.
  -u, --username        specify the user's username for pushing the Clusterimage
  -p, --password        specify the user's password for pushing the Clusterimage
  -d, --debug           show all script logs
  -h, --help            help for auto build shell scripts"
    exit 0
    ;;
  -d | --debug)
    set -x
    shift
    ;;
  -*)
    echo "Unknown option $i"
    exit 1
    ;;
  *) ;;

  esac
done

version_compare() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; } ## version_vompare $a $b:  a>=b

ARCH=$(case "$(uname -m)" in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo "unsupported architecture" "$(uname -m)" && exit 1 ;; esac)

if [ "$k8s_version" = "" ]; then echo "pls use --k8s-version to set Clusterimage kubernetes version" && exit 1; else echo "$k8s_version" | grep "v" || k8s_version="v${k8s_version}"; fi
#cri=$([[ -n "$cri" ]] && echo "$cri" || echo docker)
cri=$( (version_compare "$k8s_version" "v1.24.0" && echo "containerd") || ([[ -n "$cri" ]] && echo "$cri" || echo "docker"))
if [[ -z "$buildName" ]]; then
  buildName="registry.cn-qingdao.aliyuncs.com/sealer-io/kubernetes:${k8s_version}"
  if [[ "$cri" == "containerd" ]] && ! version_compare "$k8s_version" "v1.24.0"; then buildName=${buildName}-containerd; fi
fi
platform=$(if [[ -z "$platform" ]]; then echo "linux/arm64,linux/amd64"; else echo "$platform"; fi)
echo "cri: ${cri}, kubernetes version: ${k8s_version}, build image name: ${buildName}"

kubeadmApiVersion=$( (version_compare "$k8s_version" "v1.23.0" && echo 'kubeadm.k8s.io\/v1beta3') || (version_compare "$k8s_version" "v1.15.0" && echo 'kubeadm.k8s.io\/v1beta2') ||
  (version_compare "$k8s_version" "v1.13.0" && echo 'kubeadm.k8s.io\/v1beta1') || (echo "Version must be greater than 1.13: ${k8s_version}" && exit 1))

workdir="$(mktemp -d auto-build-XXXXX)" && sudo cp -r context "${workdir}" && cd "${workdir}/context" && sudo cp -rf "${cri}"/* .

# shellcheck disable=SC1091
sudo chmod +x version.sh download.sh && export kube_install_version="$k8s_version" && source version.sh
./download.sh "${cri}"

sudo chmod +x amd64/bin/kube* && sudo chmod +x arm64/bin/kube*
sudo wget "https://sealer.oss-cn-beijing.aliyuncs.com/sealers/sealer-v0.8.5-linux-${ARCH}.tar.gz" && sudo tar -xvf "sealer-v0.8.5-linux-${ARCH}.tar.gz"
sudo sed -i "s/v1.19.8/$k8s_version/g" rootfs/etc/kubeadm.yml ##change k8s_version
if [[ "$cri" == "containerd" ]]; then sudo sed -i "s/\/var\/run\/dockershim.sock/\/run\/containerd\/containerd.sock/g" rootfs/etc/kubeadm.yml; fi
sudo sed -i "s/kubeadm.k8s.io\/v1beta2/$kubeadmApiVersion/g" rootfs/etc/kubeadm.yml
sudo ./"${ARCH}"/bin/kubeadm config images list --config "rootfs/etc/kubeadm.yml"
sudo ./"${ARCH}"/bin/kubeadm config images list --config "rootfs/etc/kubeadm.yml" 2>/dev/null | sed "/WARNING/d" >>imageList
if [ "$(sudo ./"${ARCH}"/bin/kubeadm config images list --config rootfs/etc/kubeadm.yml 2>/dev/null | grep -c "coredns/coredns")" -gt 0 ]; then sudo sed -i "s/#imageRepository/imageRepository/g" rootfs/etc/kubeadm.yml; fi
sudo sed -i "s/k8s.gcr.io/sea.hub:5000/g" rootfs/etc/kubeadm.yml
pauseImage=$(./"${ARCH}"/bin/kubeadm config images list --config "rootfs/etc/kubeadm.yml" 2>/dev/null | sed "/WARNING/d" | grep pause)
if [ -f "rootfs/etc/dump-config.toml" ]; then sudo sed -i "s/sea.hub:5000\/pause:3.6/$(echo "$pauseImage" | sed 's/\//\\\//g')/g" rootfs/etc/dump-config.toml; fi
sudo sed -i "s/v1.19.8/${k8s_version}/g" {arm64,amd64}/etc/Metadata
##linux/arm64,linux/amd64
sudo ./sealer build -t "${buildName}" -f Kubefile --platform "${platform}" .
if [[ "$push" == "true" ]]; then
  if [[ -n "$username" ]] && [[ -n "$password" ]]; then
    sudo ./sealer login "$(echo "$buildName" | cut -d "/" -f1)" -u "${username}" -p "${password}"
  fi
  sudo ./sealer push "${buildName}"
fi
