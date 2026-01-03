#!/usr/bin/env bash
set -o errexit

die() {
  msg="$*"
  echo "[Error] ${msg}" >&2
  exit 1
}

checkEnvExist() {
  for i in "$@"; do
    if [ -z "${!i}" ]; then
      die "Please set environment ${i}"
    fi
  done
}

checkEnvExist libseccomp_version gperf_version nerdctl_version crictl_version seautil_version kube_install_version conntrack_version

cri=${1:-}
if
  [ -z "${cri}" ] || [ "${cri}" != "docker" ] && [ "${cri}" != "containerd" ]
then
  die "Usage '${0} docker' or '${0} containerd'"
fi

if [ "${cri}" = "containerd" ] && ! checkEnvExist containerd_version; then
  die "Please set environment 'containerd_version'"
fi

if [ "${cri}" = "docker" ] && ! checkEnvExist docker_version; then
  die "Please set environment 'docker_version'"
fi

gperf_url="https://ftp.gnu.org/gnu/gperf"
gperf_tarball="gperf-${gperf_version:-}.tar.gz"
gperf_tarball_url="${gperf_url}/${gperf_tarball}"

libseccomp_url="https://github.com/seccomp/libseccomp"
libseccomp_tarball="libseccomp-${libseccomp_version:-}.tar.gz"
libseccomp_tarball_url="${libseccomp_url}/releases/download/v${libseccomp_version}/${libseccomp_tarball}"

nerdctl_url="https://github.com/containerd/nerdctl"
nerdctl_tarball_amd64="nerdctl-${nerdctl_version:-}-linux-amd64.tar.gz"
nerdctl_tarball_arm64="nerdctl-${nerdctl_version}-linux-arm64.tar.gz"
nerdctl_tarball_amd64_url="${nerdctl_url}/releases/download/v${nerdctl_version}/${nerdctl_tarball_amd64}"
nerdctl_tarball_arm64_url="${nerdctl_url}/releases/download/v${nerdctl_version}/${nerdctl_tarball_arm64}"

seautil_url="https://github.com/sealerio/sealer"
seautil_tarball_amd64="seautil-v${seautil_version:-}-linux-amd64.tar.gz"
seautil_tarball_arm64="seautil-v${seautil_version}-linux-arm64.tar.gz"
seautil_tarball_amd64_url="${seautil_url}/releases/download/v${seautil_version}/${seautil_tarball_amd64}"
seautil_tarball_arm64_url="${seautil_url}/releases/download/v${seautil_version}/${seautil_tarball_arm64}"

crictl_url="https://github.com/kubernetes-sigs/cri-tools"
crictl_tarball_amd64="crictl-v${crictl_version:-}-linux-amd64.tar.gz"
crictl_tarball_arm64="crictl-v${crictl_version}-linux-arm64.tar.gz"
crictl_tarball_amd64_url="${crictl_url}/releases/download/v${crictl_version}/${crictl_tarball_amd64}"
crictl_tarball_arm64_url="${crictl_url}/releases/download/v${crictl_version}/${crictl_tarball_arm64}"

install_url="https://sealer.oss-cn-beijing.aliyuncs.com/auto-build"

##https://github.com/osemp/moby/releases/download/v19.03.14/docker-amd64.tar.gz
##registry ${ARCH} image: ghcr.io/osemp/distribution-amd64/distribution:latest
if [ "${cri}" = "docker" ]; then
  docker_url="https://download.docker.com/linux/static/stable"
  cri_tarball_amd64="docker-${docker_version}.tgz"
  cri_tarball_arm64="docker-${docker_version}.tgz"
  cri_tarball_amd64_url="${docker_url}/x86_64/${cri_tarball_amd64}"
  cri_tarball_arm64_url="${docker_url}/aarch64/${cri_tarball_arm64}"
  registry_tarball_amd64="docker-amd64-registry-image.tar.gz"
  registry_tarball_arm64="docker-arm64-registry-image.tar.gz"
  echo "download docker version ${docker_version}"

  echo "download cri-dockerd version ${cri_dockerd_version}"
  cridockerd_url="https://github.com/Mirantis/cri-dockerd/releases/download/v${cri_dockerd_version}"
  cridockerd_tarball_amd64="cri-dockerd-${cri_dockerd_version}.amd64.tgz"
  cridockerd_tarball_arm64="cri-dockerd-${cri_dockerd_version}.arm64.tgz"
  wget -q "${cridockerd_url}/${cridockerd_tarball_amd64}" && tar zxvf "${cridockerd_tarball_amd64}" -C "amd64/bin" --strip-components=1 && rm -f "${cridockerd_tarball_amd64}"
  wget -q "${cridockerd_url}/${cridockerd_tarball_arm64}" && tar zxvf "${cridockerd_tarball_arm64}" -C "arm64/bin" --strip-components=1 && rm -f "${cridockerd_tarball_arm64}"
else
  containerd_url="https://github.com/containerd/containerd"
  cri_tarball_amd64="cri-containerd-${containerd_version:-}-linux-amd64.tar.gz"
  cri_tarball_arm64="cri-containerd-${containerd_version}-linux-arm64.tar.gz"
  cri_tarball_amd64_url="${containerd_url}/releases/download/v${containerd_version}/${cri_tarball_amd64}"
  cri_tarball_arm64_url="${containerd_url}/releases/download/v${containerd_version}/${cri_tarball_arm64}"
  #registry_tarball_amd64="nerdctl-amd64-registry-image.tar.gz"
  #registry_tarball_arm64="nerdctl-arm64-registry-image.tar.gz"
  registry_tarball_amd64="docker-amd64-registry-image.tar.gz"
  registry_tarball_arm64="docker-arm64-registry-image.tar.gz"
  echo "download containerd version ${containerd_version}"
fi

registry_tarball_amd64_url="https://github.com/distribution/distribution/releases/download/v${registry_version}/registry_${registry_version}_linux_amd64.tar.gz"
registry_tarball_arm64_url="https://github.com/distribution/distribution/releases/download/v${registry_version}/registry_${registry_version}_linux_arm64.tar.gz"
echo "download registry tarball ${registry_tarball_amd64_url}"

mkdir -p {arm,amd}64/{cri,bin,images}

echo "download conntrack version ${conntrack_version}"
mkdir -p amd64/bin arm64/bin
wget -q "https://mirrors.edge.kernel.org/debian/pool/main/c/conntrack-tools/conntrack-tools_${conntrack_version}-3_amd64.deb" -O /tmp/conntrack-amd64.deb && dpkg-deb -x /tmp/conntrack-amd64.deb /tmp/conntrack-amd64 && mv /tmp/conntrack-amd64/usr/sbin/conntrack amd64/bin/ && rm -rf /tmp/conntrack-amd64 /tmp/conntrack-amd64.deb
wget -q "https://mirrors.edge.kernel.org/debian/pool/main/c/conntrack-tools/conntrack-tools_${conntrack_version}-3_arm64.deb" -O /tmp/conntrack-arm64.deb && dpkg-deb -x /tmp/conntrack-arm64.deb /tmp/conntrack-arm64 && mv /tmp/conntrack-arm64/usr/sbin/conntrack arm64/bin/ && rm -rf /tmp/conntrack-arm64 /tmp/conntrack-arm64.deb

echo "download gperf version ${gperf_version}"
mkdir -p "rootfs/lib"
curl -sLO "${gperf_tarball_url}" && mv "${gperf_tarball}" "rootfs/lib"

echo "download libseccomp version ${libseccomp_version}"
curl -sLO "${libseccomp_tarball_url}" && mv "${libseccomp_tarball}" "rootfs/lib"

echo "download nerdctl version ${nerdctl_version}"
wget -q "https://github.com/containerd/nerdctl/releases/download/v${nerdctl_version}/nerdctl-${nerdctl_version}-linux-amd64.tar.gz" -O nerdctl-amd64.tar.gz && tar zxvf nerdctl-amd64.tar.gz -C "amd64/bin" --strip-components=1 && rm -f nerdctl-amd64.tar.gz
wget -q "https://github.com/containerd/nerdctl/releases/download/v${nerdctl_version}/nerdctl-${nerdctl_version}-linux-arm64.tar.gz" -O nerdctl-arm64.tar.gz && tar zxvf nerdctl-arm64.tar.gz -C "arm64/bin" --strip-components=1 && rm -f nerdctl-arm64.tar.gz

echo "download crictl version ${crictl_version}"
wget -q "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${crictl_version}/crictl-v${crictl_version}-linux-amd64.tar.gz" -O crictl-amd64.tar.gz && tar zxvf crictl-amd64.tar.gz -C "amd64/bin" && rm -f crictl-amd64.tar.gz
wget -q "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${crictl_version}/crictl-v${crictl_version}-linux-arm64.tar.gz" -O crictl-arm64.tar.gz && tar zxvf crictl-arm64.tar.gz -C "arm64/bin" && rm -f crictl-arm64.tar.gz

echo "download seautil version ${seautil_version}"
wget -q "https://github.com/sealerio/sealer/releases/download/v${seautil_version}/seautil-v${seautil_version}-linux-amd64.tar.gz" -O seautil-amd64.tar.gz && tar zxvf seautil-amd64.tar.gz -C "amd64/bin" && rm -f seautil-amd64.tar.gz
wget -q "https://github.com/sealerio/sealer/releases/download/v${seautil_version}/seautil-v${seautil_version}-linux-arm64.tar.gz" -O seautil-arm64.tar.gz && tar zxvf seautil-arm64.tar.gz -C "arm64/bin" && rm -f seautil-arm64.tar.gz

echo "download cri with ${cri} : ${cri_tarball_amd64_url}"
wget -q "${cri_tarball_amd64_url}" && mv "${cri_tarball_amd64}" "amd64/cri/docker.tar.gz"
wget -q "${cri_tarball_arm64_url}" && mv "${cri_tarball_arm64}" "arm64/cri/docker.tar.gz"

echo "download registry image from Docker Hub"
mkdir -p amd64/images arm64/images
docker pull --platform linux/amd64 registry:${registry_version} && docker save registry:${registry_version} -o amd64/images/registry.tar.gz && docker rmi registry:${registry_version}
docker pull --platform linux/arm64 registry:${registry_version} && docker save registry:${registry_version} -o arm64/images/registry.tar.gz && docker rmi registry:${registry_version}

echo "download kubeadm kubectl kubelet version ${kube_install_version:-}"

for i in "kubeadm" "kubectl" "kubelet"; do
  sudo curl -L "https://dl.k8s.io/release/${kube_install_version}/bin/linux/amd64/${i}" -o "amd64/bin/${i}"
  sudo curl -L "https://dl.k8s.io/release/${kube_install_version}/bin/linux/arm64/${i}" -o "arm64/bin/${i}"
done

echo "after download.sh . amd64/cri"
echo "$(ls -la amd64/cri)"
