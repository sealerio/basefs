# Design

## CloudImage rootfs

All the files which run a kubernetes cluster needs of CloudImage.

Contains:

* Bin files, like docker, containerd, crictl ,kubeadm, kubectl...
* Config files, like kubelet systemd config, docker systemd config, docker daemon.json...
* Registry docker image.
* Some Metadata, like Kubernetes version.
* Registry files, contains all the docker image, like kubernetes core component docker images...
* Scripts, some shell script using to install docker and kubelet... sealer will call init.sh and clean.sh.
* Other static files

completely rootfs dendrogram

```
.
├── bin
│   ├── conntrack
│   ├── containerd-rootless-setuptool.sh
│   ├── containerd-rootless.sh
│   ├── crictl
│   ├── kubeadm
│   ├── kubectl
│   ├── kubelet
│   ├── nerdctl
│   └── seautil
├── cri
│   └── docker.tar.gz # cri bin files include docker,containerd,runc.
├── etc
│   ├── 10-kubeadm.conf
│   ├── Clusterfile  # image default Clusterfile
│   ├── daemon.json # docker daemon config file.
│   ├── docker.service
│   ├── kubeadm.yml # kubeadm config including Cluster Configuration,JoinConfiguration and so on.
│   ├── kubelet.service
│   ├── registry_config.yml # docker registry config including storage root directory and http related config.
│   └── registry.yml # If the user wants to customize the username and password, can overwrite this file.
├── images
│   └── registry.tar  # registry docker image, will load this image and run a local registry in cluster
├── Kubefile
├── Metadata
├── README.md
├── registry # will mount this dir to local registry
│   └── docker
│       └── registry
├── scripts
│   ├── clean.sh
│   ├── docker.sh
│   ├── init-kube.sh
│   ├── init-registry.sh
│   ├── init.sh
│   └── kubelet-pre-start.sh
└── statics # yaml files, sealer will render values in those files
    └── audit-policy.yml
```

## Build Rootfs

### Local repo context

include base rootfs("etc","scrips","statics","registry") and CRI context("etc","scrips"), and CNI context.

local repo context dendrogram:

```
├── context
│   ├── Kubefile
│   ├── calico
│   │   ├── Kubefile
│   │   ├── custom-resources.yaml
│   │   ├── imageList
│   │   └── tigera-operator.yaml
│   ├── containerd
│   │   ├── etc
│   │   │   └── dump-config.toml
│   │   └── scripts
│   │       ├── clean.sh
│   │       ├── containerd.sh
│   │       ├── init-registry.sh
│   │       └── init.sh
│   ├── docker
│   │   ├── etc
│   │   │   ├── daemon.json
│   │   │   └── docker.service
│   │   └── scripts
│   │       ├── clean.sh
│   │       ├── docker.sh
│   │       ├── init-registry.sh
│   │       └── init.sh
│   ├── imageList
│   └── rootfs
│       ├── etc
│       │   ├── 10-kubeadm.conf
│       │   ├── Clusterfile
│       │   ├── kubeadm.yml
│       │   ├── kubelet.service
│       │   ├── registry.yml
│       │   └── registry_config.yml
│       ├── registry
│       ├── scripts
│       │   ├── clean-kube.sh
│       │   ├── init-kube.sh
│       │   └── kubelet-pre-start.sh
│       └── statics
│           └── audit-policy.yml
```

### OSS context

#### rootfsContext

oss rootfs context dendrogram:

```
├── amd64
│   ├── bin
│   │   ├── conntrack
│   │   ├── containerd-rootless-setuptool.sh
│   │   ├── containerd-rootless.sh
│   │   ├── crictl
│   │   ├── nerdctl
│   │   └── seautil
│   └── Metadata
├── arm64
│   ├── bin
│   │   ├── conntrack
│   │   ├── containerd-rootless-setuptool.sh
│   │   ├── containerd-rootless.sh
│   │   ├── crictl
│   │   ├── nerdctl
│   │   └── seautil
│   └── Metadata
```

#### ${cri}Context

1. oss docker context dendrogram:

```
├── amd64
│   ├── cri
│   │   └── docker.tar.gz
│   └── images
│       └── registry.tar.gz
├── arm64
│   ├── cri
│   │   └── docker.tar.gz
│   └── images
│       └── registry.tar.gz
```

2. oss containerd context dendrogram:

```
├── amd64
│   ├── cri
│   │   ├── containerd.tar.gz
│   │   └── lib64
│   │       ├── libseccomp.so.2
│   │       └── libseccomp.so.2.5.1
│   └── images
│       └── registry.tar.gz
├── arm64
│   ├── cri
│   │   ├── containerd.tar.gz
│   │   └── lib64
│   │       ├── libseccomp.so.2
│   │       └── libseccomp.so.2.5.1
│   └── images
│       └── registry.tar.gz
```

### Build directory

completely build context dendrogram at build stage which merged base rootfs, oss rootfs, cir context and kube* files:

```
├── amd64
│   ├── bin
│   │   ├── conntrack
│   │   ├── containerd-rootless-setuptool.sh
│   │   ├── containerd-rootless.sh
│   │   ├── crictl
│   │   ├── kubeadm
│   │   ├── kubectl
│   │   ├── kubelet
│   │   ├── nerdctl
│   │   └── seautil
│   ├── cri
│   │   └── docker.tar.gz
│   ├── images
│   │   └── registry.tar
│   └── Metadata
├── arm64
│   ├── bin
│   │   ├── conntrack
│   │   ├── containerd-rootless-setuptool.sh
│   │   ├── containerd-rootless.sh
│   │   ├── crictl
│   │   ├── kubeadm
│   │   ├── kubectl
│   │   ├── kubelet
│   │   ├── nerdctl
│   │   └── seautil
│   ├── cri
│   │   └── docker.tar.gz
│   ├── images
│   │   └── registry.tar
│   └── Metadata
└── rootfs
├── etc
│   ├── 10-kubeadm.conf
│   ├── Clusterfile
│   ├── daemon.json
│   ├── docker.service
│   ├── kubeadm.yml.tmpl
│   ├── kubelet.service
│   ├── registry_config.yml
│   └── registry.yml
├── imageList
├── Kubefile
├── registry
├── scripts
│   ├── clean-kube.sh
│   ├── clean.sh
│   ├── docker.sh
│   ├── init-kube.sh
│   ├── init-registry.sh
│   ├── init.sh
│   └── kubelet-pre-start.sh
└── statics
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

docker default sock addr : "/var/run/dockershim.sock"
containerd default sock addr : "/run/containerd/containerd.sock"

3, imageRepository for kubeadm.yml

imageList use native repo `k8s.gcr.io` which generated from imageRepository of kubeadm.yml ,

we modify the imageRepository to `sea.hub:5000` for pulling from our private registry.

4, dns imageRepository for kubeadm.yml

if output of `kubeadm config images list` looks like `k8s.gcr.io/coredns/coredns:1.8.6`,

then we need set dns section of ClusterConfiguration:

```yaml
dns:
  imageRepository: ${repo domain}/coredns
```

5, containerd config file:
keep same pause version with imageList.

if imageList use `pause:3.6`,then `sandbox_image = "${repo domain}/pause:3.6"`

