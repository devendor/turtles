#!/bin/bash
set -xe
GIT_DIR=$(dirname "$(readlink -f "$0")")
REPO_DIR=xenial-compat
PKG_DIR=binary-amd64
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

cd "$GIT_DIR"

if [ -d ${REPO_DIR} ] ; then
    rm -rf ${REPO_DIR}
fi

mkdir -p ${REPO_DIR}/${PKG_DIR}
cd ${REPO_DIR}/${PKG_DIR}
apt-get download -y "${PACKAGES[@]}"

cd "${GIT_DIR}"

apt-ftparchive packages ${REPO_DIR}/${PKG_DIR} > ${REPO_DIR}/Packages 
apt-ftparchive release ${REPO_DIR} > ${REPO_DIR}/Release
gpg2 --default-key 4AEB593D7E2663ECA0EF1A40C9FF73F21EC3DCD9 --armor \
    --output ${REPO_DIR}/Release.gpg --detach-sign ${REPO_DIR}/Release 
gpg --armor --export github.public@devendortech.com  > ${REPO_DIR}/gpg.key

cat > ${REPO_DIR}/README.md <<"END"
# Description

A small collection of packages from the 18.04LTS ubuntu distro that can be installed on a 16.04LTS
LXC Guest over 18.04 host to allows accellerated GPU support in the guest.

# Use

curl https://raw.githubusercontent.com/devendor/turtles/master/xenial-compat/gpg.key -o - | apt-key add -
apt-add-repository "deb  https://raw.githubusercontent.com/devendor/turtles/master xenial-compat/"

END

