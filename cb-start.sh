#!/bin/bash
#
# This script is to assist in maintaining a fork of chromium by routinely
# building with a patch rebased on the latest release from a chromium
# channel (we carry one for dev and one for stable).
#
# It's split into 2 parts, cb-start and cb-continue.
# - cb-start will pull down the code, check out at a release, apply the
#   last known good patch, and rebase, then call cb-continue if it
#   succeeds.
# - cb-continue will do the build.
#
# This is meant to be a starting entry for a docker container, but also
# to be interactively runnable in the (common) event that the rebase
# fails.  After fixing and pulling the patch out, cb-continue tries to
# finish the build.

# env variable options:
# VERSION: the commit comes from "git checkout $VERSION".  If no
#   version is provided the default comes from the linux dev version
#   from https://omahaproxy.appspot.com/all.json  (generally this is
#   one of the version tags, you can see them in the mirror at
#   https://github.com/chromium/chromium)
# ARGSFILE: if set and file present it will use this as args.gn
#   instead of the default.
# PATCHSPEC: environment variable, exclusive with PATCHFILE.  This will
#   set PATCHFILE=/tmp/patch.diff, and will generate the 
#   git apply it. The git apply happens in a "patched_build" branch
#   forked from the latest common ancestor of $VERSION and main.
# LASTGOOD: environment variable that applies the patch first to a
#   specific version, then tries to rebase VERSION on top of it.  When
#   patches fail, this allows for fixing afterward in a more normal
#   git merge workflow.
#
set -e

DIR=/bld
export PATH="${PATH}:${DIR}/depot_tools"

# you should be able to do a docker start -i <container> to come back up
# in an interactive shell and troubleshoot after a failed build (this is
# the purpose of this weird bash call when /bld is already present.)
if [ -d ${DIR}/src ]; then
  cd ${DIR}/src
  bash -i
  exit
fi

early_stop=0
if [ "${ARGSFILE}" != "" -a ! -f "${ARGSFILE}" ]; then
    echo "error: ARGSFILE not present, please unset or get the file in place and re-run"
    echo "ARGSFILE=\"${ARGSFILE}\""
    early_stop=1
fi

if [ "${PATCHFILE}" = "" -a "${PATCHSPEC}" = "" ]; then
    echo "error: PATCHFILE and PATCHSPEC both not set, please pass one to cb-start.sh"
    exit 1
fi

if [ "${PATCHFILE}" != "" -a "${PATCHSPEC}" != "" ]; then
    echo "error: PATCHFILE=${PATCHFILE} and PATCHSPEC=${PATCHSPEC} both set, please pass only one to cb-start.sh"
    exit 1
fi

if [ "${PATCHFILE}" != "" -a ! -f "${PATCHFILE}" ]; then
    echo "error: ${PATCHFILE} not present, please unset or get the file in place and re-run"
    echo "PATCHFILE=\"${PATCHFILE}\""
    early_stop=1
fi

if [ "${early_stop}" != "0" ]; then
    exit 1
fi

# from https://stackoverflow.com/a/22373735/3427357
exec > >(tee /tmp/out.log) 2>&1

mkdir -p ${DIR}

if [ "${VERSION}" = "" ]; then
  VERSION=$(curl https://omahaproxy.appspot.com/all.json | jq -r '.[].versions[] | select(.os=="linux") | select(.channel=="dev") | .version' | head -1)
fi

echo "VERSION=${VERSION}" | tee /tmp/version.log
cat > /tmp/env.sh <<EOF
VERSION=${VERSION}
LASTGOOD=${LASTGOOD}
CHAN=${CHAN}
BP=$(echo ${VERSION} | cut -f -3 -d.)
EOF

set -x

cd ${DIR}
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git

fetch chromium
# build instructions say to do the below instead, but it fails.
#fetch --nohooks chromium
# https://chromium.googlesource.com/chromium/src/+/master/docs/linux/build_instructions.md#get-the-code
# --jake 2021-03-15

cd src
git checkout ${VERSION}

mkdir -p out/Default

if [ "${ARGSFILE}" != "" -a -f "${ARGSFILE}" ]; then
    cp "${ARGSFILE}" out/Default/args.gn
else
    cat > out/Default/args.gn <<EOF
is_debug=false
is_component_build=false
blink_symbol_level=1
symbol_level=1
enable_nacl=false
enable_linux_installer=true
ffmpeg_branding="Chrome"
proprietary_codecs=true
EOF
fi

git remote add multicast https://github.com/GrumpyOldTroll/chromium.git
git fetch multicast --tags

if [ "${PATCHSPEC}" != "" ]; then
  PATCHFILE=/bld/src/out/Default/patch.diff
  git diff ${PATCHSPEC} > ${PATCHFILE}
fi
echo "DIFF_SHA256=\"$(shasum -a 256 ${PATCHFILE} | awk '{print $1;}')\"" > out/Default/DIFF_SHA.sh
cp /tmp/env.sh out/Default/

./build/install-build-deps.sh --no-prompt

# for some reason install-build-deps now removes python-is-python3, but
# gclient sync fails without it with bad dependencies.
sudo apt-get install -y python-is-python3

gclient sync

git apply ${PATCHFILE}

gn gen out/Default
autoninja -C out/Default chrome
ninja -C out/Default "chrome/installer/linux:unstable_deb"
