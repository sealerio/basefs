#!/bin/bash

set -e
set -x
# prepare registry storage as directory
cd $(dirname "$0")

REGISTRY_PORT=${1-5000}
VOLUME=${2-/var/lib/registry}
REGISTRY_DOMAIN=${3-sea.hub}

container=sealer-registry
rootfs=$(dirname "$(pwd)")
config="$rootfs/etc/registry_config.yml"
htpasswd="$rootfs/etc/registry_htpasswd"
certs_dir="$rootfs/certs"
image_dir="$rootfs/images"

mkdir -p "$VOLUME" || true

startRegistry() {
    n=1
    while (( n <= 3 ))
    do
        echo "attempt to start registry"
        (docker start $container && break) || (( n < 3))
        (( n++ ))
        sleep 3
    done
}

load_images() {
for image in "$image_dir"/*
do
 if [ -f "${image}" ]
 then
  docker load -q -i "${image}"
 fi
done
}

check_registry() {
    n=1
    while (( n <= 3 ))
    do
        registry_status=$(docker inspect --format '{{json .State.Status}}' sealer-registry)
        if [[ "$registry_status" == \"running\" ]]; then
            break
        fi
        if [[ $n -eq 3 ]]; then
           echo "sealer-registry is not running, status: $registry_status"
           exit 1
        fi
        (( n++ ))
        sleep 3
    done
}

load_images

## rm container if exist.
if [ "$(docker ps -aq -f name=$container)" ]; then
    docker rm -f $container
fi

regArgs="-d --restart=always \
--net=host \
--name $container \
-v $certs_dir:/certs \
-v $VOLUME:/var/lib/registry \
-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/$REGISTRY_DOMAIN.crt \
-e REGISTRY_HTTP_TLS_KEY=/certs/$REGISTRY_DOMAIN.key"

if [ -f $config ]; then
    sed -i "s/5000/$1/g" $config
    regArgs="$regArgs \
    -v $config:/etc/docker/registry/config.yml"
fi

if [ -f $htpasswd ]; then
    docker run $regArgs \
            -v $htpasswd:/htpasswd \
            -e REGISTRY_AUTH=htpasswd \
            -e REGISTRY_AUTH_HTPASSWD_PATH=/htpasswd \
            -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" registry:2.7.1 || startRegistry
else
    docker run $regArgs registry:2.7.1 || startRegistry
fi

check_registry