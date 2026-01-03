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
echo "this is init-registry.sh -----------------------------"
set -e
set -x

# Detect CRI tool
if command -v nerdctl >/dev/null 2>&1; then
    CRI_BIN="nerdctl"
else
    CRI_BIN="docker"
fi

# prepare registry storage as directory
# shellcheck disable=SC2046
cd "$(dirname "$0")"

# shellcheck disable=SC2034
REGISTRY_PORT="${1:-5000}"
VOLUME="${2:-/var/lib/registry}"
REGISTRY_DOMAIN="${3:-sea.hub}"

container="sealer-registry"
rootfs="$(dirname "$(pwd)")"
config="$rootfs/etc/registry_config.yml"
htpasswd="$rootfs/etc/registry_htpasswd"
certs_dir="$rootfs/certs"
image_dir="$rootfs/images"

echo "registry VOLUME:$VOLUME"
mkdir -p "$VOLUME" || true

load_images() {
    if [ -d "$image_dir" ]; then
        for image in "$image_dir"/*
        do
            if [ -f "${image}" ]; then
                "$CRI_BIN" load -q -i "${image}"
            fi
        done
    fi
}

check_registry() {
    local n=1
    while (( n <= 3 ))
    do
        registry_status=$("$CRI_BIN" inspect --format '{{json .State.Status}}' "$container" 2>/dev/null || echo "unknown")
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
if [ "$("$CRI_BIN" ps -aq -f "name=^/${container}$")" ]; then
    "$CRI_BIN" rm -f "$container"
fi

regArgs="-d --restart=always \
--net=host \
--name $container \
-v $certs_dir:/certs \
-v $VOLUME:/var/lib/registry \
-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/$REGISTRY_DOMAIN.crt \
-e REGISTRY_HTTP_TLS_KEY=/certs/$REGISTRY_DOMAIN.key \
-e REGISTRY_HTTP_DEBUG_ADDR=0.0.0.0:5002 \
-e REGISTRY_HTTP_DEBUG_PROMETHEUS_ENABLED=true \
-e REGISTRY_STORAGE_DELETE_ENABLED=true"

# shellcheck disable=SC2086
if [ -f "$config" ]; then
    sed -i "s/5000/${REGISTRY_PORT}/g" "$config"
    regArgs="$regArgs \
    -v $config:/etc/docker/registry/config.yml"
fi

# Try to run registry with retries
run_registry() {
    local n=1
    while (( n <= 3 ))
    do
        echo "attempt $n to run registry"
        if [ -f "$htpasswd" ]; then
            if "$CRI_BIN" run $regArgs \
                    -v "$htpasswd":/htpasswd \
                    -e REGISTRY_AUTH=htpasswd \
                    -e REGISTRY_AUTH_HTPASSWD_PATH=/htpasswd \
                    -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" registry:2.7.1; then
                return 0
            fi
        else
            if "$CRI_BIN" run $regArgs registry:2.7.1; then
                return 0
            fi
        fi
        (( n++ ))
        sleep 3
        "$CRI_BIN" rm -f "$container" 2>/dev/null || true
    done
    return 1
}

run_registry
check_registry

echo "rootfs: $rootfs"
echo "$(ls -l "$rootfs")"

if [ -d "$certs_dir" ]; then
  echo "certs_dir: $certs_dir"
  echo "$(ls -l "$certs_dir")"
  if [ -f "$certs_dir/$REGISTRY_DOMAIN.crt" ]; then
    # For Docker
    DOCKER_CERT_FOLDER="/etc/docker/certs.d/$REGISTRY_DOMAIN:$REGISTRY_PORT"
    mkdir -p "$DOCKER_CERT_FOLDER"
    cp -f "$certs_dir/$REGISTRY_DOMAIN.crt" "$DOCKER_CERT_FOLDER/ca.crt"
    
    # For Containerd (nerdctl)
    CONTAINERD_CERT_FOLDER="/etc/containerd/certs.d/$REGISTRY_DOMAIN:$REGISTRY_PORT"
    mkdir -p "$CONTAINERD_CERT_FOLDER"
    cp -f "$certs_dir/$REGISTRY_DOMAIN.crt" "$CONTAINERD_CERT_FOLDER/ca.crt"
  fi
fi
