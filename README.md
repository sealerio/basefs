# Rootfs

## Introduction

in order to support user build base CloudImage automatically,open this repo and share the related rootfs files. user can
use `auto-build` to do this job and meanwhile using git hub action with issue comment to do it. at the same time you can
use this repo to customize your own base CloudImage such as choosing the different CRI plugin version or CNI plugin
version,even the default kubernetes cluster configuration and so on.

## How to use auto-build

auto-build only accept one arg that is image version,and will use this version to pull related kubernetes container
images, so make sure it is a valid value.

### default build

this is will build the CloudImage named "kubernetes:v1.22.8" without CNI plugin. and both have two platform: amd64 and
arm64 platform. that means you got four CloudImages at the same time.

```shell
auto-build v1.22.8
```

### build with specify platform

this will build a CloudImage with amd64 platform.

```shell
auto-build v1.22.8 --platform amd64
```

### build with specify CRI

this will build a CloudImage with containerd. if user not specify the CRI ,we use containerd as CloudImage default cri.

```shell
auto-build v1.22.8 --cri docker
```

### build with customized CloudImage name

this will build a CloudImage named `registry.cn-qingdao.aliyuncs.com/sealer-io/myk8s:v1.22.8`

```shell
auto-build v1.22.8 --name registry.cn-qingdao.aliyuncs.com/sealer-io/myk8s:v1.22.8
```

### build without pushing

if `--no-push=true`,then only save at the local repo,default option is pushing to ALI Cloud ACR, and need login first.

```shell
auto-build v1.22.8 --no-push
```
