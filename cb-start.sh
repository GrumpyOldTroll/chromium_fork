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
# PATCHURL: if set it will curl this and git apply it.  You can get
#   these from github commits, e.g.:
#   https://github.com/GrumpyOldTroll/chromium/commit/da79e14e808debadfd1743222bcacd7dad41fdbe.patch
# PATCHFILE: environment variable, if set and file present it will
#   git apply it. The git apply happens in a "patched_build" branch
#   forked from the latest common ancestor of $VERSION and main.
#   NB: if both PATCHURL and PATCHFILE are set it will error. PATCHURL
#       fetches early to /tmp/patch.diff and uses PATCHFILE internally.
# LASTGOOD: environment variable that applies the patch first to a
#   specific version, then tries to rebase VERSION on top of it.  When
#   patches fail, this allows for fixing afterward in a more normal
#   git merge workflow.
#
set -e

DIR=/bld
export PATH="${PATH}:${DIR}/depot_tools"

if [ -d ${DIR}/src ]; then
    bash ; exit
# you should be able to do a docker start -i <container> to come back up
# in an interactive shell and troubleshoot after a failed build (this is
# the purpose of this weird bash call when /bld is already present.)
fi

early_stop=0
if [ "${ARGSFILE}" != "" -a ! -f "${ARGSFILE}" ]; then
    echo "error: ARGSFILE not present, please unset or get the file in place and re-run"
    echo "ARGSFILE=\"${ARGSFILE}\""
    early_stop=1
fi

if [ "${PATCHFILE}" != "" -a ! -f "${PATCHFILE}" ]; then
    echo "error: PATCHFILE not present, please unset or get the file in place and re-run"
    echo "PATCHFILE=\"${PATCHFILE}\""
    early_stop=1
fi

if [ "${PATCHURL}" != "" -a "${PATCHFILE}" != "" ]; then
    echo "error: PATCHURL and PATCHFILE should not both be set, please unset one and re-run"
    echo "PATCHURL=\"${PATCHURL}\""
    echo "PATCHFILE=\"${PATCHFILE}\""
    early_stop=1
fi

if [ "${early_stop}" != "0" ]; then
    exit 1
fi

if [ "${GITEMAIL}" = "" ]; then
  GITEMAIL="jholland@akamai.com"
fi
if [ "${GITNAME}" = "" ]; then
  GITNAME="Jake Holland"
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
EOF

if [ "${PATCHURL}" != "" ]; then
  PATCHFILE=/tmp/patch.diff
  echo "fetching PATCHURL=\"${PATCHURL}\""
  curl -q -s --fail > ${PATCHFILE}
else
  PATCHURL="(local file)"
fi

set -x

cd ${DIR}
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git

fetch chromium
#fetch --nohooks chromium

cd src
git checkout ${VERSION}
if [ "${PATCHFILE}" != "" -a -f ${PATCHFILE} ]; then
  git config user.email "${GITEMAIL}"
  git config user.name "${GITNAME}"
  PATCHID=$(shasum ${PATCHFILE} | awk '{print $1};')
  if [ "${PATCHURL}" != "" ]; then
    PATCHID="${PATCHID}(${PATCHURL})"
  else
    PATCHID="${PATCHID}(${PATCHFILE})"
  fi
  echo "PATCHID=\"${PATCHID}\"" >> /tmp/env.sh
  if [ "${LASTGOOD}" != "" ]; then
    # wind back to last common commit as the merge base to avoid DEPS and chrome/VERSION conflicts
    VERSIONBRANCH=$(git merge-base main ${VERSION})
    LASTGOODBRANCH=$(git merge-base main ${LASTGOOD})
    echo "VERSIONBRANCH=${VERSIONBRANCH}" >> /tmp/env.sh
    echo "LASTGOODBRANCH=${LASTGOODBRANCH}" >> /tmp/env.sh

    # TBD: it's possible that a different patch is needed for the last
    # common ancestor vs. the current head of the branch, so maybe I need
    # 2 patches here?
    # the issue is that merging directly from a last good commit to a new
    # commit gets a bunch of spurious errors in DEPS and chrome/VERSION,
    # and patching on top of a common ancestor in main does not (as these
    # version-specific things are added only to the version branches)

    git checkout -b patched_build ${LASTGOODBRANCH}
    git apply ${PATCHFILE}

    git add -A
    git commit -m "automated apply of version ${LASTGOOD} patch ${PATCHID}"
    # TBD: should this run as 2 separate stages?  they can both fail then,
    # which means a 2-step fix.  If I need 2 patches, above, I probably
    # need 2 stages here, but I think I'll put it off until it happens a
    # few times.
    # git rebase ${VERSIONBRANCH}
    git rebase ${VERSION}
  else
    git checkout -b patched_build
    git apply ${PATCHFILE}
    git add .
  fi
fi

. /root/cb-continue.sh

