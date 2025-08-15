#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export DEB_BUILD_OPTIONS=nocheck
if [ "$SYSTEMD" = true ]; then
  export DEB_BUILD_OPTIONS="systemd $DEB_BUILD_OPTIONS"
fi

build() {
  path="$1"
  [ -d $path ] || return 0
  cd $path
  if ! check_arch; then
    echo "## Skip $path ##"
    echo "## No packages to build for $(dpkg-architecture -qDEB_HOST_ARCH)"
    return 0
  fi
  echo "## Build $path ##"
  apt-get build-dep -y .
  if [ "$path" != /build/xlibre ]; then
    uscan --download-current-version
  fi
  debuild -us -uc
}

check_arch() {
  host_arch="$(dpkg-architecture -qDEB_HOST_ARCH)"
  pkg_arch=" $(grep -i '^Architecture:' debian/control | cut -d' ' -f2- | xargs) "
  echo "$pkg_arch" | grep -qE " ($host_arch|any-$host_arch|any|all|linux-any) "
}

build /build/xlibre-server
apt-get install -y /build/*.deb

if ls /build/xserver-xlibre-* >/dev/null 2>&1; then
  for path in /build/xserver-xlibre-*; do
    build $path
  done
fi
build /build/xlibre