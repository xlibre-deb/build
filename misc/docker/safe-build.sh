#!/bin/bash
set -o pipefail

if SYSTEMD=${SYSTEMD} bash /build/build.sh | tee /tmp/build.log; then
  rm -rf /build/build.sh /build/safe-build.sh /build/*/
else
  mv /build /tmp/failed-build
  mkdir /build
  mv /tmp/failed-build /build/
  >&2 echo "ERROR: Build failed!"
fi

mv /tmp/build.log /build/