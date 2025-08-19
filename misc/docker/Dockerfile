ARG BASEIMAGE=debian:unstable

FROM ${BASEIMAGE} AS base
ARG SYSTEMD=true

WORKDIR /build
COPY misc/docker/install-reqs.sh ./
RUN SYSTEMD=${SYSTEMD} bash /build/install-reqs.sh

FROM base AS build
ARG PACKAGES=*
ARG SYSTEMD

WORKDIR /build
COPY misc/docker/build.sh ./
COPY misc/docker/safe-build.sh ./

RUN --mount=type=bind,source=packages,target=/tmp/packages \
  cd /tmp/packages && \
  cp -r ${PACKAGES} /build/

RUN SYSTEMD=${SYSTEMD} bash /build/safe-build.sh
RUN rm -rf /var/lib/apt/lists/*

FROM scratch AS export
ARG TARGET_NAME=debian-unstable-amd64
COPY --from=build /build/ ./${TARGET_NAME}/