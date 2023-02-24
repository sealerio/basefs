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

set -e
set -x
# prepare registry storage as directory
# shellcheck disable=SC2046
cd $(dirname "$0")

# shellcheck disable=SC2034
REGISTRY_PORT=${1-5000}
VOLUME=${2-/var/lib/registry}
REGISTRY_DOMAIN=${3-sea.hub}
REGISTRY_TYPE=${4-docker}

container=sealer-registry
rootfs=$(dirname "$(pwd)")
config="$rootfs/etc/registry_config.yml"
oci_config="$rootfs/etc/oci_registry_config.json"
htpasswd="$rootfs/etc/registry_htpasswd"
certs_dir="$rootfs/certs"
image_dir="$rootfs/images"

mkdir -p "$VOLUME" || true

# shellcheck disable=SC2106
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

# shellcheck disable=SC2034
# shellcheck disable=SC2089
ociConfig="{ \
  \"distspecversion\": \"1.0.1-dev\", \
  \"storage\": { \
    \"rootdirectory\": \"/var/lib/registry\" \
  }, \
  \"http\": { \
    \"address\": \"0.0.0.0\", \
    \"port\": $1, \
    \"realm\": \"zot\", \
    \"tls\": {
      \"cert\": \"/certs/$REGISTRY_DOMAIN.cert\", \
      \"key\": \"/certs/$REGISTRY_DOMAIN.key\" \
    } \
  } \
}"

# shellcheck disable=SC2034
# shellcheck disable=SC2089
ociConfigAuth="{ \
  \"distspecversion\": \"1.0.1-dev\", \
  \"storage\": { \
    \"rootdirectory\": \"/var/lib/registry\" \
  }, \
  \"http\": { \
    \"address\": \"0.0.0.0\", \
    \"port\": $1, \
    \"realm\": \"zot\", \
    \"tls\": {
      \"cert\": \"/certs/$REGISTRY_DOMAIN.cert\", \
      \"key\": \"/certs/$REGISTRY_DOMAIN.key\" \
    }, \
    \"auth\": { \
      \"htpasswd\": { \
        \"path\": \"/etc/zot/htpasswd\" \
      } \
    } \
  } \
}"

regArgs="-d --restart=always \
--net=host \
--name $container \
-v $VOLUME:/var/lib/registry"

# shellcheck disable=SC2086
if [ "$REGISTRY_TYPE" == "docker" ]; then
  regArgs="$regArgs \
  -v $certs_dir:/certs \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/$REGISTRY_DOMAIN.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/$REGISTRY_DOMAIN.key \
  -e REGISTRY_HTTP_DEBUG_ADDR=0.0.0.0:5002 \
  -e REGISTRY_HTTP_DEBUG_PROMETHEUS_ENABLED=true"
  # shellcheck disable=SC2086
  if [ -f $config ]; then
      sed -i "s/5000/$1/g" $config
      regArgs="$regArgs \
      -v $config:/etc/docker/registry/config.yml"
  fi
  # shellcheck disable=SC2086
  if [ -f $htpasswd ]; then
      docker run $regArgs \
              -v $htpasswd:/htpasswd \
              -e REGISTRY_AUTH=htpasswd \
              -e REGISTRY_AUTH_HTPASSWD_PATH=/htpasswd \
              -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" registry:2.7.1 || startRegistry
  else
      docker run $regArgs registry:2.7.1 || startRegistry
  fi
else # oci registry
  regArgs="$regArgs \
  -v $oci_config:/etc/zot/config.json
  -v $certs_dir/$REGISTRY_DOMAIN.crt:/certs/$REGISTRY_DOMAIN.cert \
  -v $certs_dir/$REGISTRY_DOMAIN.key:/certs/$REGISTRY_DOMAIN.key"
   # shellcheck disable=SC2086
   if [ -f $htpasswd ]; then
       # shellcheck disable=SC2090
       echo $ociConfigAuth > $oci_config
       docker run $regArgs \
               -v $htpasswd:/etc/zot/htpasswd \
               ghcr.io/project-zot/zot-linux-amd64:v1.4.3 || startRegistry
   else
       # shellcheck disable=SC2090
       echo $ociConfig > $oci_config
       docker run $regArgs ghcr.io/project-zot/zot-linux-amd64:v1.4.3 || startRegistry
   fi
fi

check_registry