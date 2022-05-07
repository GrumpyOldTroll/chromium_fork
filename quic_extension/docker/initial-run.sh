#!/bin/bash

set -e

DIR=/build
if [ ! -d ${DIR} ]; then
  echo "the container should be mounted to a directory at /build that's writable by the --build-arg USER_ID=\$(id -u \${USER}) from the docker build. (see chromium_fork/quic_extension/docker/README.md)"
  exit 1
fi

export PATH="${PATH}:${DIR}/depot_tools"

# you should be able to do a docker start -i <container> to come back up
# in an interactive shell.
if [ -d ${DIR}/src ]; then
  cd ${DIR}/src
  bash -i
  exit
fi

set -x

cd ${DIR}
if [ ! -d depot_tools ]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

fetch chromium

cd src/

git remote add multicast https://github.com/GrumpyOldTroll/chromium.git
git fetch multicast
git checkout quic-multicast-dev

pushd net/third_party/quiche/src
git remote add multicast https://github.com/GrumpyOldTroll/quiche.git
git fetch multicast
git checkout quic-multicast-dev
popd

git apply /base/fix.patch
./build/install-build-deps.sh --no-prompt
gclient sync -D

pushd net/third_party/quiche/src
git checkout quic-multicast-dev
git pull
popd
git checkout quic-multicast-dev
git pull

mkdir -p out/Default
cat > out/Default/args.gn <<EOF
is_debug=true
is_component_build=false
blink_symbol_level=1
symbol_level=2
enable_nacl=false
enable_linux_installer=true
ffmpeg_branding="Chrome"
proprietary_codecs=true
EOF

gn gen out/Default

