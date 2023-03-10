# Customize sealer image

Build image file context [@basefs](https://github.com/sealerio/basefs)

All the files which run a kubernetes cluster needs of sealer image.

Contains:

* Bin files, like docker, containerd, crictl ,kubeadm, kubectl...
* Config files, like kubelet systemd config, docker systemd config, docker daemon.json...
* Registry docker image.
* Registry files, contains all the docker image, like kubernetes core component docker images...
* Scripts, some shell script using to install docker and kubelet... sealer will call init.sh and clean.sh.
* Other static files

## rootfs dendrogram

completely build context dendrogram at build stage which merged base rootfs, oss rootfs, cir context and kube* files:

```
.
├── application # app file, including chart package, script, yaml file.
│   └── apps
│       └── calico
│           └── calico.sh
├── applications
│   ├── custom-resources.yaml
│   └── tigera-operator.yaml
├── bin  # some binaries
│   ├── conntrack
│   ├── containerd-rootless-setuptool.sh
│   ├── containerd-rootless.sh
│   ├── crictl
│   ├── kubeadm
│   ├── kubectl
│   ├── kubelet
│   ├── nerdctl
│   └── seautil
├── cri # cri bin files include docker,containerd,runc.
│   └── docker.tar.gz
├── etc
│   ├── 10-kubeadm.conf
│   ├── daemon.json  # docker daemon config file.
│   ├── docker.service
│   ├── kubeadm.yml # kubeadm config including Cluster Configuration,JoinConfiguration and so on.
│   ├── kubeadm.yml.tmpl # kubeadm.yaml file template
│   ├── kubelet.service
│   └── registry_config.yml # docker registry config including storage root directory and http related config.
├── images # registry cri images.
│   └── docker-amd64-registry-image.tar.gz # registry docker image, will load this image and run a local registry in cluster.
├── lib # library file directory
│   ├── gperf-3.1.tar.gz
│   ├── install_libseccomp.sh
│   └── libseccomp-2.5.4.tar.gz
├── manifests # when the sealer builds, it will parse all the yaml files under this directory and extract the address of the container image inside, and then pull
│   └── imageList # this is a special file that contains a list of other mirror addresses that need to be pulled. For example, the mirror address cannot be resolved by the sealer in the CRD, so it needs to be manually configured in this file.
├── registry # will mount this dir to local registry
│   └── docker
│       └── registry
├── scripts # store script files
│   ├── docker.sh
│   ├── init-kube.sh
│   ├── init-registry.sh
│   ├── kubelet-pre-start.sh
│   └── uninstall-docker.sh
└── statics # yaml files, sealer will render values in those files
    └── audit-policy.yml
```

## Special case for note

1. kubeadmApiVersion for kubeadm.yml

```
a. apiversion in ["v1.23.0",) : 'kubeadm.k8s.io/v1beta3')
b. apiversion in [v1.15.0,v1.23.0) : 'kubeadm.k8s.io/v1beta2')
c. apiversion in (v1.15.0,v1.23.0] : 'kubeadm.k8s.io/v1beta1')
```

2. criSocket for kubeadm.yml

```shell
docker default sock addr : "/var/run/dockershim.sock"
containerd default sock addr : "/run/containerd/containerd.sock"
```

3. imageRepository for kubeadm.yml

imageList use native repo `k8s.gcr.io` which generated from imageRepository of kubeadm.yml ,

we modify the imageRepository to `sea.hub:5000` for pulling from our private registry.

4. dns imageRepository for kubeadm.yml

if output of `kubeadm config images list` looks like `k8s.gcr.io/coredns/coredns:1.8.6`,

then we need set dns section of ClusterConfiguration:

```yaml
dns:
  imageRepository: ${repo domain}/coredns
```

5. containerd config file:
   keep same pause version with imageList.

if imageList use `pause:3.6`,then `sandbox_image = "${repo domain}/pause:3.6"`

## How to customize CRI

### Modify config

#### Docker

configure daemon.json, Example:

```shell
cat > ./context/docker/rootfs/etc/daemon.json <<EOF
{
  "max-concurrent-downloads": 20,
  "log-driver": "json-file",
  "log-level": "warn",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "mirror-registries": [
    {
      "domain": "*",
      "mirrors": [
        "https://sea.hub:5000"
      ]
    }
  ],
  "exec-opts": [
    "native.cgroupdriver=systemd"
  ],
  "data-root": "/var/lib/docker"
}
EOF
```

configure docker.service, Example:

```shell
cat > ./context/docker/rootfs/etc/docker.service <<EOF
{
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecStartPost=/usr/sbin/iptables -P FORWARD ACCEPT
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process

[Install]
WantedBy=multi-user.target
}
EOF
```

if the docker version is modified, then we need to modify the `docker.sh` file:

```yaml
DOCKER_VERSION="19.03.14-sealer"
```

then you have to modify the docker url for `download.sh`:

```shell
cri_tarball_amd64_url="https://github.com/osemp/moby/releases/download/v19.03.14/docker-amd64.tar.gz"
```

#### Containerd

modify dump-config.toml, Example:

```shell
cat > ./context/docker/rootfs/etc/dump-config.toml <<EOF
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "sea.hub:5000/pause:3.6"
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/docker/certs.d/"
EOF
```

modify containerd.service, Example:

```shell
cat > ./context/docker/rootfs/etc/containerd.service <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=1048576
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
```

if you need to modify the `containerd` version, you can modify the `version.sh` script, Example:

```shell
export containerd_version=${containerd_version:-"1.6.12"}
```

## How to customize kubeadm

### Modify kubeadm.yml.tmpl

if you need to modify the imageRepository, you can modify the `kubeadm.yml.tmpl` file, Example:

```yaml
imageRepository: {{or .RegistryURL "sea.hub:5000"}}
```

if you need to modify the networking, you can modify the `kubeadm.yml.tmpl` file, Example:

```shell
networking:
  podSubnet: 100.64.0.0/10
  serviceSubnet: 10.96.0.0/22
```

## How to use imageList

If you need to download an additional image, you can put the image that needs to be downloaded into the imageList, so
that the image will be automatically downloaded to the registry when building, Example:

```shell
cat >> ./context/imageList << EOF
docker.io/sealerio/lvscare:v1.1.3-beta.8
quay.io/tigera/operator:v1.25.3
calico/node:v3.22.1
calico/pod2daemon-flexvol:v3.22.1
calico/cni:v3.22.1
calico/kube-controllers:v3.22.1
calico/typha:v3.22.1
calico/apiserver:v3.22.1
EOF
```

## How to customize registry

modify registry_config.yml, Example:

```shell
cat > ./context/rootfs/etc/registry_config.yml << EOF
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: 5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
```

if you need to modify docker registry.tar.gz, you can modify the `download.sh` file, Example:

```shell
cri_tarball_amd64_url="https://github.com/osemp/moby/releases/download/v19.03.14/docker-amd64.tar.gz"
```

## How to use auto-build

auto-build only accept one arg that is image version,and will use this version to pull related kubernetes container
images, so make sure it is a valid value.

```shell
## auto-build options:
  --k8s-version         set the kubernetes k8s_version of the Clusterimage, k8s_version must be greater than 1.13
  -c, --cri             cri can be set to docker or containerd between kubernetes 1.20-1.24 versions
  -n, --buildName       set build image name, default is 'registry.cn-qingdao.aliyuncs.com/sealer-io/kubernetes:${k8s_version}'
  --platform            set the build mirror platform, the default is linux/amd64,linux/arm64
  --push                push clusterimage after building the clusterimage. The image name must contain the full name of the repository, and use -u and -p to specify the username and password.
  -u, --username        specify the user's username for pushing the Clusterimage
  -p, --password        specify the user's password for pushing the Clusterimage
  -d, --debug           show all script logs
  -h, --help            help for auto build shell scripts
```

### default build

this is will build the Clusterimage named "kubernetes:v1.22.8" without CNI plugin. and both have two platform: amd64 and
arm64 platform. that means you got four Clusterimages at the same time.

```shell
auto-build --k8s-version=v1.22.15
```

### build with specify platform

this will build a Clusterimage with amd64 platform, default is linux/amd64,linux/arm64.

```shell
auto-build --k8s-version=v1.22.15 --platform=amd64
```

### build with specified name

this will build a Clusterimage with amd64 platform.

```shell
auto-build --k8s-version=v1.22.15 --buildName=registry.cn-qingdao.aliyuncs.com/sealer-io/kubernetes:v1.22.15
```

### build with customized Clusterimage name

this will build a Clusterimage named `registry.cn-qingdao.aliyuncs.com/sealer-io/myk8s:v1.22.8`

```shell
auto-build --k8s-version=v1.22.15 --buildName=registry.cn-qingdao.aliyuncs.com/sealer-io/myk8s:v1.22.8
```

### build without pushing

if `--push`, push the clusterimage to the image registry. The image name must contain the full name of the repository.

```shell
auto-build --k8s-version=v1.22.15 --buildName=registry.cn-qingdao.aliyuncs.com/sealer-io/kubernetes:v1.22.8 --push
```

The image warehouse address is registry.cn-qingdao.aliyuncs.com.

If you do not log in to the mirror warehouse, you need to use -u and -p to specify the username and password

```shell
auto-build --k8s-version=v1.22.15 --buildName=registry.cn-qingdao.aliyuncs.com/sealer-io/kubernetes:v1.22.8 --push --username=specifyUser --password=specifyPasswd
```

## Auto-build case

build:

```shell
auto-build --k8s-version=v1.22.15 --platform=amd64
```

### The following is the context of Kubefile and ImageList generated after automatic construction

Kubefile:

```dockerfile
FROM scratch
COPY rootfs .
COPY amd64 .
COPY imageList manifests
LABEL "cluster.alpha.sealer.io/cluster-runtime-version"="v1.22.15"
LABEL "cluster.alpha.sealer.io/cluster-runtime-type"="kubernetes"
LABEL "cluster.alpha.sealer.io/container-runtime-type"="docker"
LABEL "cluster.alpha.sealer.io/container-runtime-version"="19.03.14"
COPY tigera-operator.yaml applications/tigera-operator.yaml
COPY custom-resources.yaml applications/custom-resources.yaml
CNI calico local://calico.sh
LAUNCH ["calico"]
```

imageList:

```shell
docker.io/sealerio/lvscare:v1.1.3-beta.8
quay.io/tigera/operator:v1.25.3
calico/node:v3.22.1
calico/pod2daemon-flexvol:v3.22.1
calico/cni:v3.22.1
calico/kube-controllers:v3.22.1
calico/typha:v3.22.1
calico/apiserver:v3.22.1
k8s.gcr.io/kube-apiserver:v1.22.15
k8s.gcr.io/kube-controller-manager:v1.22.15
k8s.gcr.io/kube-scheduler:v1.22.15
k8s.gcr.io/kube-proxy:v1.22.15
k8s.gcr.io/pause:3.5
k8s.gcr.io/etcd:3.5.0-0
k8s.gcr.io/coredns/coredns:v1.8.4
```