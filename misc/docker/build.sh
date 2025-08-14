#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

if [ "$SYSTEMD" = true ]; then
  export DEB_BUILD_OPTIONS=systemd
fi

build() {
  path="$1"
  [ -d $path ] || return 0
  cd $path
  echo "## Build $path ##"
  apt-get build-dep -y .
  if [ "$path" != /build/xlibre ]; then
    uscan --download-current-version
  fi
  debuild -us -uc
}

build /build/xlibre-server
apt-get install -y /build/*.deb

if ls /build/xserver-xlibre-* >/dev/null 2>&1; then
  for path in /build/xserver-xlibre-*; do
    build $path
  done
fi
build /build/xlibre