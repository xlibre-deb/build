#!/bin/bash
set -e

export BUILD_DIR="$1"
export DEBIAN_FRONTEND=noninteractive
export DEB_BUILD_OPTIONS=nocheck
if [ "$SYSTEMD" != true ]; then
  export DEB_BUILD_PROFILES=nosystemd
fi

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
if [ "$CODENAME" == bookworm ] || [ "$CODENAME" == trixie ] \
|| [ "$CODENAME" == daedalus ] || [ "$CODENAME" == excalibur ] \
|| [ "$CODENAME" == noble ] || [ "$CODENAME" == plucky ] || [ "$CODENAME" == questing ]
then
  export DEB_BUILD_PROFILES="xatracker $DEB_BUILD_PROFILES"
fi

build() {
  path="$1"
  [ -d "$path" ] || return 0
  cd "$path"
  if ! check_arch; then
    echo "## Skip $path ##"
    echo "## No packages to build for $(dpkg-architecture -qDEB_HOST_ARCH)"
    return 0
  fi
  echo "## Build $path ##"
  apt-get build-dep -y .

  # unless native package
  if ! [ -f debian/source/format ] || ! grep -q 'native' debian/source/format; then
    git branch pristine-tar origin/pristine-tar >/dev/null 2>&1 ||:
  fi

  gbp buildpackage -uc -us \
    --git-pristine-tar \
    --git-ignore-branch \
    --git-upstream-branch=upstream/latest \
    --git-debian-branch=xlibre/latest
}

check_arch() {
  host_arch="$(dpkg-architecture -qDEB_HOST_ARCH)"
  pkg_arch=" $(grep -i '^Architecture:' debian/control | cut -d' ' -f2- | xargs) "
  echo "$pkg_arch" | grep -qE " ($host_arch|any-$host_arch|any|all|linux-any) "
}

build "$BUILD_DIR/xorgproto"
apt-get install -y "$BUILD_DIR"/x11proto*.deb

build "$BUILD_DIR/xlibre"
apt-get install -y "$BUILD_DIR"/xlibre-x11-common*.deb

build "$BUILD_DIR/xlibre-server"
apt-get install -y "$BUILD_DIR"/xserver-xlibre-dev*.deb

if ls "$BUILD_DIR"/xserver-xlibre-*/ >/dev/null 2>&1; then
  for path in "$BUILD_DIR"/xserver-xlibre-*/; do
    build "$path"
  done
fi
