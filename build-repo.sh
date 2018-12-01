#!/bin/bash
set -xe
GIT_DIR=$(dirname $(readlink -f $0))
REPO_DIR=${GIT_DIR}/xenial-compat
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
    git rm -rf ${REPO_DIR} || rm -rf ${REPO_DIR}
fi

mkdir -p ${REPO_DIR}/amd64

cd ${REPO_DIR}/amd64
apt-get download -y "${PACKAGES[@]}"
cd ${GIT_DIR}
apt-ftparchive packages $(basename ${REPO_DIR})/amd64 | gzip - > ${REPO_DIR}/amd64/Packages.gz

