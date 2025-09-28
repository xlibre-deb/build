#!/bin/bash
set -o pipefail

if SYSTEMD=${SYSTEMD} bash /build/build.sh /build 2>&1 | tee /tmp/build.log; then
  rm -rf /build/build.sh /build/safe-build.sh /build/*/
  echo success > /build/build-status
else
  mv /build /tmp/failed-build
  mkdir /build
  mv /tmp/failed-build /build/
  >&2 echo "ERROR: Build failed!"
  echo failure > /build/build-status
fi

mv /tmp/build.log /build/