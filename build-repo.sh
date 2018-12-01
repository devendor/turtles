#!/bin/bash
set -xe
REPO_DIR=$(dirname $(readlink -f $0))/xenial-compat
PACKAGES=(
    libgl1
    libgl1-mesa-glx
    libglapi-mesa
    libglvnd0
    libglx0
    libglx-mesa0
    libnvidia-common-390
    libnvidia-gl-390
    libxcb-glx0
    mesa-utils
    x11-utils
)

if [ -d ${REPO_DIR} ] ; then
    rm -rf ${REPO_DIR};
fi

mkdir ${REPO_DIR}
cd ${REPO_DIR}
apt-get download -y "${PACKAGES[@]}"
apt-ftparchive packages . | gzip - > Packages.gz

