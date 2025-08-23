#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
if [ "$CODENAME" == bookworm ]; then
  cat <<EOF > /etc/apt/sources.list.d/debian.sources
Types: deb
URIs: http://deb.debian.org/debian
Suites: bookworm bookworm-updates bookworm-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: bookworm-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

  apt-get update
  apt-get install -y --no-install-recommends -t bookworm-backports \
    libdrm-dev libudev-dev libdbus-1-dev libsystemd-dev systemd-dev
  apt-get install -y --no-install-recommends \
    devscripts
  exit 0
elif [ "$CODENAME" == daedalus ]; then
  rm -f /etc/apt/sources.list
  mkdir -p /etc/apt/sources.list.d/
  cat <<EOF > /etc/apt/sources.list.d/devuan.sources
Types: deb
URIs: http://deb.devuan.org/merged
Suites: daedalus daedalus-security daedalus-updates daedalus-backports
Components: main
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
EOF

  apt-get update
  apt-get install -y --no-install-recommends -t daedalus-backports \
    libdrm-dev
  apt-get install -y --no-install-recommends \
    devscripts
  exit 0
fi

if [ "${SYSTEMD}" = true ]; then
  apt_add_pkgs="libdbus-1-dev libsystemd-dev systemd-dev"
fi

apt-get update
apt-get install -y --no-install-recommends \
  devscripts $apt_add_pkgs
