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
cd "$(dirname "$0")"

# shellcheck disable=SC2034
REGISTRY_PORT=${1-5000}
VOLUME=${2-/var/lib/registry}
REGISTRY_DOMAIN=${3-sea.hub}

container=sealer-registry
rootfs=$(dirname "$(pwd)")
config="$rootfs/etc/registry_config.yml"
htpasswd="$rootfs/etc/registry_htpasswd"
certs_dir="$rootfs/certs"

mkdir -p "$VOLUME" || true

startRegistry() {
    n=1
    while (( n <= 3 ))
    do
        echo "attempt to start registry"
        # shellcheck disable=SC2106
        (nerdctl start $container && break) || (( n < 3))
        (( n++ ))
        sleep 3
    done
}

check_registry() {
    n=1
    while (( n <= 3 ))
    do
        (nerdctl inspect sealer-registry | grep "\"Status\": \"running\"") && break
        if [[ $n -eq 3 ]]; then
           # shellcheck disable=SC2154
           echo "sealer-registry is not running, status: $registry_status"
           exit 1
        fi
        (( n++ ))
        sleep 3
    done
}


## rm container if exist.
! nerdctl ps -a |grep sealer-registry || nerdctl rmi -f sealer-registry
##
rm -rf /var/lib/nerdctl/1935db59/names/default/$container

regArgs="-d --restart=always \
--net=host \
--name $container \
-v $certs_dir:/certs \
-v $VOLUME:/var/lib/registry \
-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/$REGISTRY_DOMAIN.crt \
-e REGISTRY_HTTP_TLS_KEY=/certs/$REGISTRY_DOMAIN.key"

if [ -f "$config" ]; then
    sed -i "s/5000/$1/g" "$config"
    regArgs="$regArgs \
    -v $config:/etc/docker/registry/config.yml"
fi

if [ -f "$htpasswd" ]; then
    # shellcheck disable=SC2086
    nerdctl run $regArgs \
            -v $htpasswd:/htpasswd \
            -e REGISTRY_AUTH=htpasswd \
            -e REGISTRY_AUTH_HTPASSWD_PATH=/htpasswd \
            -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" registry:2.7.1 || startRegistry
else
    nerdctl run "$regArgs" registry:2.7.1 || startRegistry
fi

sleep 1
check_registry