# syntax=docker/dockerfile:1
# see https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact
ARG DISTRIBUTION=almalinux
ARG DISTRO_VERSN=9
ARG PLATFORM=amd64

FROM --platform=linux/${PLATFORM} ${DISTRIBUTION}:${DISTRO_VERSN}

# set the environment variables that gha sets
ENV DISTRO_VERSN=9
ENV INPUT_SFTP_SERVER=""
ENV INPUT_SFTP_USER=""
ENV INPUT_SFTP_REMOTE_PATH=""

# Install build environment
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EORUN
 [ -x /usr/bin/apt-get ] && apt-get update && apt-get install sshfs dpkg-dev
 [ -x /usr/bin/dnf ] && dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-${DISTRO_VERSN}.noarch.rpm && dnf install -y createrepo fuse fuse-sshfs
EORUN

COPY ./build.sh .

RUN chmod u+x build.sh

# Script to execute when the docker container starts up
ENTRYPOINT ["bash", "/build.sh"]