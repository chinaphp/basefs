#!/bin/bash

set -e
echo "auto-build.sh parse input parameter ..."

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
  --docker-namespace=*)
    docker_namespace="${i#*=}"
    shift # past argument=value
    ;;
  --docker-registry=*)
    docker_registry="${i#*=}"
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

echo "This is auto-build.sh"
version_compare() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; } ## version_compare $a $b:  a>=b

ARCH=$(case "$(uname -m)" in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo "unsupported architecture" "$(uname -m)" && exit 1 ;; esac)

if [[ -z "$docker_namespace" ]]; then
  docker_namespace="chinaphp"
fi

if [[ -z "$dockerRegistry" ]]; then
  dockerRegistry="docker.io"
fi

if [ "$k8s_version" = "" ]; then echo "pls use --k8s-version to set Clusterimage kubernetes version" && exit 1; else echo "$k8s_version" | grep "v" || k8s_version="v${k8s_version}"; fi
cri=$([[ -n "$cri" ]] && echo "$cri" || echo "containerd")
#cri=$( (version_compare "$k8s_version" "v1.24.0" && echo "containerd") || ([[ -n "$cri" ]] && echo "$cri" || echo "docker"))
if [[ -z "$buildName" ]]; then
  buildName="${dockerRegistry}/$docker_namespace/kubernetes:${k8s_version}"
  if [[ "$cri" == "containerd" ]] && ! version_compare "$k8s_version" "v1.24.0"; then buildName=${buildName}-containerd; fi
fi
platform=$(if [[ -z "$platform" ]]; then echo "linux/arm64,linux/amd64"; else echo "$platform"; fi)
echo "final cri: ${cri}, kubernetes version: ${k8s_version}, build image name: ${buildName}"

kubeadmApiVersion=$( (version_compare "$k8s_version" "v1.23.0" && echo 'kubeadm.k8s.io\/v1beta3') || (version_compare "$k8s_version" "v1.15.0" && echo 'kubeadm.k8s.io\/v1beta2') ||
  (version_compare "$k8s_version" "v1.13.0" && echo 'kubeadm.k8s.io\/v1beta1') || (echo "Version must be greater than 1.13: ${k8s_version}" && exit 1))

echo "kubeadmApiVersion: ${kubeadmApiVersion}"

workdir="$(mktemp -d auto-build-XXXXX)" && sudo cp -r context "${workdir}" && cd "${workdir}/context" && sudo cp -rf "${cri}"/* .

echo "after make workdir: ${workdir}/context/rootfs/scripts"
echo "$(ls -l rootfs/scripts)"

# shellcheck disable=SC1091
echo "run download.sh"
sudo chmod +x version.sh download.sh && export kube_install_version="$k8s_version" && source version.sh
./download.sh "${cri}"

sudo chmod +x amd64/bin/* && sudo chmod +x arm64/bin/*
#download v0.11.0
# sudo wget https://github.com/sealerio/sealer/releases/download/v0.11.0/sealer-v0.11.0-linux-amd64.tar.gz && tar -xvf sealer-v0.11.0-linux-amd64.tar.gz -C /usr/bin
sudo wget https://github.com/chinaphp/sealer/releases/download/v0.11.11/sealer-v0.11.11-linux-amd64.tar.gz && tar -xvf sealer-v0.11.11-linux-amd64.tar.gz -C /usr/bin
sudo sed -i "s/v1.19.8/$k8s_version/g" rootfs/etc/kubeadm.yml ##change k8s_version
sudo sed -i "s/v1.19.8/$k8s_version/g" rootfs/etc/kubeadm.yml.tmpl ##change k8s_version
sudo sed -i "s/v1.19.8/$k8s_version/g" Kubefile ##change k8s_version
if [[ "$cri" == "docker" ]]; then
  runtime_version="$docker_version"
else
  runtime_version="$containerd_version"
fi
sudo sed -i "s/\"cluster.alpha.sealer.io\/container-runtime-type\"=\"[^\"]*\"/\"cluster.alpha.sealer.io\/container-runtime-type\"=\"$cri\"/g" Kubefile
sudo sed -i "s/\"cluster.alpha.sealer.io\/container-runtime-version\"=\"[^\"]*\"/\"cluster.alpha.sealer.io\/container-runtime-version\"=\"$runtime_version\"/g" Kubefile
sudo sed -i "s/registry:2.7.1/registry:${registry_version}/g" rootfs/scripts/init-registry.sh
if [[ "$cri" == "containerd" ]]; then
  cri_socket="unix:///run/containerd/containerd.sock"
else
  cri_socket="/var/run/dockershim.sock"
fi
sed "s|{{CRI_SOCKET}}|$cri_socket|g" rootfs/etc/kubeadm.yml > rootfs/etc/kubeadm.yml.tmp && sudo mv rootfs/etc/kubeadm.yml.tmp rootfs/etc/kubeadm.yml
sed "s|{{CRI_SOCKET}}|$cri_socket|g" rootfs/etc/kubeadm.yml.tmpl > rootfs/etc/kubeadm.yml.tmpl.tmp && sudo mv rootfs/etc/kubeadm.yml.tmpl.tmp rootfs/etc/kubeadm.yml.tmpl
sudo sed -i "s/kubeadm.k8s.io\/v1beta2/$kubeadmApiVersion/g" rootfs/etc/kubeadm.yml
sudo sed -i "s/kubeadm.k8s.io\/v1beta2/$kubeadmApiVersion/g" rootfs/etc/kubeadm.yml.tmpl
sudo ./"${ARCH}"/bin/kubeadm config images list --config "rootfs/etc/kubeadm.yml"

sudo mkdir -p rootfs/manifests
sudo ./"${ARCH}"/bin/kubeadm config images list --config "rootfs/etc/kubeadm.yml" 2>/dev/null | sed "/WARNING/d" >>imageList
if [ "$(sudo ./"${ARCH}"/bin/kubeadm config images list --config rootfs/etc/kubeadm.yml 2>/dev/null | grep -c "coredns/coredns")" -gt 0 ]; then sudo sed -i "s/#imageRepository/imageRepository/g" rootfs/etc/kubeadm.yml.tmpl; fi
sudo sed -i "s/registry.k8s.io/sea.hub:5000/g" rootfs/etc/kubeadm.yml.tmpl
pauseImage=$(./"${ARCH}"/bin/kubeadm config images list --config "rootfs/etc/kubeadm.yml" 2>/dev/null | sed "/WARNING/d" | grep pause)

echo "pauseImage: $pauseImage"
if [ -f "rootfs/etc/dump-config.toml" ]; then sudo sed -i "s/sea.hub:5000\/pause:3.6/$(echo "$pauseImage" | sed 's/\//\\\//g')/g" rootfs/etc/dump-config.toml; fi

# fix
if [ -f "rootfs/kubeadm.yaml" ];then
  sudo sed -i '/dpIdleTimeout: 0s/d' rootfs/kubeadm.yaml
else
  echo "rootfs/kubeadm.yaml not exist now!"
fi

echo "before build workdir: ${workdir}/context/rootfs"
echo "$(ls -l rootfs)"

echo "before build workdir: ${workdir}/context/rootfs/scripts"
echo "$(ls -l rootfs/scripts)"

echo "before build workdir: ${workdir}/context/rootfs/etc"
echo "$(ls -l rootfs/etc)"

# Ensure all scripts have execution permissions
sudo chmod +x rootfs/scripts/*

echo "$(sealer version)}"
echo "build name: $buildName"
sudo sealer build -t "$buildName" -f Kubefile
if [[ "$push" == "true" ]]; then
  echo "hub username: $username"
  if [[ -n "$username" ]] && [[ -n "$password" ]]; then
    sudo sealer login "$(echo "$docker_registry" | cut -d "/" -f1)" -u "${username}" -p "${password}"
  fi
  echo "push name: $buildName"
  sudo sealer push "$buildName"
  sudo sealer images
  sudo sealer inspect "$buildName"
fi
