#!/bin/bash

set -e

if [ "${CHAN}" = "" ]; then
    CHAN=dev
fi

WORK=nightly-junk
mkdir -p ${WORK}
LOGF=${WORK}/chrome-build-nightly.${CHAN}.log

# from https://stackoverflow.com/a/22373735/3427357
#exec > /tmp/out.log 2>&1

CN=cbuild-${CHAN}
CI=${CN}
DKR=docker

PREV_RUNNING=$(${DKR} container inspect ${CN} 2> /dev/null) | jq -r ".[].State.Running"
if [ "${PREV_RUNNING}" = "true" ]; then
    echo "$(date) docker container ${CN} already running" | tee -a ${LOGF}
    exit 1
fi

CLEANED_REPORT=""
if [ "${PREV_RUNNING}" = "false" ]; then
    # 1-week grace period on cleaning a prior build failure
    GRACE=$((7 * 86400))
    echo "$(date) docker container ${CN} exists and is stopped" | tee -a ${LOGF}
    PREV_CREATED=$(${DKR} container inspect ${CN} | jq -r ".[].Created")
    OLD=$(date +'%s' -d "${PREV_CREATED}")
    NOW=$(date +'%s')
    SINCE=$(python -c "print(${NOW}-${OLD})")
    if [ "${SINCE}" -lt "${GRACE}" ]; then
	echo "$(date) exiting nightly build (build from ${PREV_CREATED} inside 1-week grace period on existing container" | tee -a ${LOGF}
	exit 1
    fi
    echo "old enough to proceed by cleaning up (${SINCE}s > ${GRACE}s), cleaning" | tee -a ${LOGF}
    CLEANED_REPORT="cleaned old container from ${PREV_CREATED}"
    ${DKR} container rm ${CN}
fi

if [ "${VER}" = "" ]; then
  JF=${WORK}/chromium-nightly.${CHAN}.json
  if ! curl -q -f -s https://omahaproxy.appspot.com/all.json > ${JF} ; then
    echo "$(date) failed curl of https://omahaproxy.appspot.com/all.json to get release version info" | tee -a ${LOGF}
    exit 1
  fi
  VER=$(cat ${JF}| jq -r ".[].versions[] | select(.os==\"linux\") | select(.channel==\"$CHAN\") | .version" | head -1)
  BRANCH=$(cat ${JF}| jq -r ".[].versions[] | select(.os==\"linux\") | select(.channel==\"$CHAN\") | .branch_commit" | head -1)
  echo "pulled VER=${VER} (BRANCH=${BRANCH}) from release info at https://omahaproxy.appspot.com/all.json" | tee -a ${LOGF}
  AUTOUPDATE_LASTGOOD=1
else
  echo "explicit override of version: VER=${VER}" | tee -a ${LOGF}
  BRANCH="manual-VER-${VER}-NO-EXPLICIT-BRANCH"
  if [ "${POST}" = "1" ]; then
    AUTOUPDATE_LASTGOOD=1
  else
    AUTOUPDATE_LASTGOOD=0
  fi
fi

. LAST_GOOD.${CHAN}.sh

if [ "${USE_PATCH}" != "" ]; then
  echo "explicit override on patch: setting LAST_GOOD_DIFF_FILE=${USE_PATCH} instead of ${LAST_GOOD_DIFF_FILE}" | tee -a ${LOGF}
  LAST_GOOD_DIFF_FILE="${USE_PATCH}"
  LAST_GOOD_DIFF_SPEC=""
fi

if [ "${LAST_GOOD_DIFF_SPEC}" != "" -a "${LAST_GOOD_DIFF_FILE}" != "" ]; then
  echo "$(date) both LAST_GOOD_DIFF_FILE (${LAST_GOOD_DIFF_FILE}) and LAST_GOOD_DIFF_SPEC (${LAST_GOOD_DIFF_SPEC}) are set, please unset one" | tee -a ${LOGF}
  exit 1
fi

if [ "${LAST_GOOD_DIFF_FILE}" != "" -a ! -f "${LAST_GOOD_DIFF_FILE}" ]; then
    echo "$(date) no such file LAST_GOOD_DIFF_FILE=${LAST_GOOD_DIFF_FILE} (from LAST_GOOD.${CHAN}.sh" | tee -a ${LOGF}
    exit 1
fi

#ABS_LAST_GOOD_DIFF=$(python -c "from os.path import abspath; print(abspath('${LAST_GOOD_DIFF_FILE}'))")
#CUR_SHA256=$(shasum -a 256 ${LAST_GOOD_DIFF_FILE} | awk '{print $1;}')

#if [ "${CUR_SHA256}" = "${LAST_GOOD_DIFF_SHA256}" -a "${LAST_GOOD_TAG}" = "${VER}" -a "${LAST_GOOD_BRANCH}" = "${BRANCH}" ]; then
#    echo "$(date) chromium channel=${CHAN} is unchanged from last good: VER=${VER}, BRANCH=${BRANCH}" | tee -a ${LOGF}
#    exit 1
#fi

if [ "${LAST_GOOD_TAG}" = "${VER}" -a "${LAST_GOOD_BRANCH}" = "${BRANCH}" -a "${LAST_GOOD_DIFF_SPEC}" != "" ]; then
    echo "$(date) chromium channel=${CHAN} is unchanged from last good: VER=${VER}, BRANCH=${BRANCH}" | tee -a ${LOGF}
    exit 0
fi

echo "${CHAN} build ${VER} start at $(date)" | tee -a ${LOGF}

echo "" > ${WORK}/PROPOSED.${CHAN}.sh
if [ "${LAST_GOOD_DIFF_SPEC}" != "" ]; then
  echo "LAST_GOOD_DIFF_SPEC=\"${LAST_GOOD_DIFF_SPEC}\"" >> ${WORK}/PROPOSED.${CHAN}.sh
  echo "#LAST_GOOD_DIFF_FILE=" >> ${WORK}/PROPOSED.${CHAN}.sh
else
  echo "#LAST_GOOD_DIFF_SPEC=" >> ${WORK}/PROPOSED.${CHAN}.sh
  echo "LAST_GOOD_DIFF_FILE=\"${LAST_GOOD_DIFF_FILE}\"" >> ${WORK}/PROPOSED.${CHAN}.sh
fi
echo "LAST_GOOD_BRANCH=${BRANCH}" >> ${WORK}/PROPOSED.${CHAN}.sh

if [ "$SILENT" != "" ]; then
    exec > ${LOGF} 2>&1
else
    exec > >(tee ${LOGF}) 2>&1
fi

STARTTIME=$(date +"%Y%m%d-%H%M%S")
echo "chromium build ${VER} (channel ${CHAN}) started at ${STARTTIME} (PWD=${PWD})"
echo ${CLEANED_REPORT}

set -x

# might need sudo sometimes?  might need full path sometimes? might need args sometimes?
DKR=docker

${DKR} pull ubuntu:focal

if [ "${LAST_GOOD_DIFF_SPEC}" != "" ]; then
  cat Dockerfile.base \
    | sed -e "s@PATCH_LINE1@ENV PATCHSPEC=\"${LAST_GOOD_DIFF_SPEC}\"@" \
    | sed -e "s@PATCH_LINE2@@" \
    > ${WORK}/Dockerfile.${CHAN}
else
  cat Dockerfile.base \
    | sed -e "s@PATCH_LINE1@ENV PATCHFILE=\"/tmp/patch.diff\"@" \
    | sed -e "s@PATCH_LINE2@COPY ${LAST_GOOD_DIFF_FILE} /tmp/patch.diff@" \
    > ${WORK}/Dockerfile.${CHAN}
fi
#  | sed -e "s@PROPOSEDFILE@${WORK}/PROPOSED.${CHAN}.sh@" \
#${DKR} build --file ${WORK}/Dockerfile.${CHAN}.latest --tag ${CI}:latest .
${DKR} build --file ${WORK}/Dockerfile.${CHAN} \
  --build-arg USER_ID=$(id -u ${USER}) \
  --build-arg GROUP_ID=$(id -g ${USER}) \
  --tag ${CI}:latest .

BLDDIR=$(mktemp -d -t chrome-build-XXXXXX)
rm -f ${WORK}/bld-${CHAN}
ln -s ${BLDDIR} ${WORK}/bld-${CHAN}

# NB: the snap socket is needed for snapcraft during build-dependencies.
# Note # also there exists docker setups able to run snaps, e.g.:
# https://github.com/ogra1/snapd-docker/blob/master/build.sh, however it
# seems to need a different entrypoint that's less convenient for my usage,
# so I do it this way, which uses the host's snap socket. --jake 2021-03-20
${DKR} run --name ${CN} -d \
	--env VERSION=${VER} \
	--env LASTGOOD=${LAST_GOOD_TAG} \
	--env CHAN=${CHAN} \
  -v ${BLDDIR}:/bld \
	-v /run/snapd.socket:/run/snapd.socket ${CI}:latest

${DKR} logs -f ${CN}

#${DKR} cp ${CN}:/bld/src/out/Default/chromium-browser-mc-unstable_${VER}-1_amd64.deb ${WORK}/
OUTFNAME=chromium-browser-mc-unstable_${VER}-1_amd64.deb
mv ${WORK}/bld-${CHAN}/src/out/Default/${OUTFNAME} ${WORK}/

echo "LAST_GOOD_TAG=${VER}" >> ${WORK}/PROPOSED.${CHAN}.sh

# docker cp ${CN}:where-the-.deb-is .
# we expect this file to be built by the docker container, and for it
# to set DIFF_SHA256.
cp ${WORK}/bld-${CHAN}/src/out/Default/DIFF_SHA.sh ${WORK}/DIFF_SHA.${CHAN}.sh
. ${WORK}/DIFF_SHA.${CHAN}.sh
echo "LAST_GOOD_DIFF_SHA256=\"${DIFF_SHA256}\"" >> ${WORK}/PROPOSED.${CHAN}.sh
echo "LAST_GOOD_DEB_SHA256=\"$(shasum -a 256 ${WORK}/${OUTFNAME} | awk '{print $1;}')\"" >> ${WORK}/PROPOSED.${CHAN}.sh

${DKR} image prune -f
${DKR} rm ${CN}

if [ "${AUTOUPDATE_LASTGOOD}" = "1" ]; then
  ROTATION=10
  # SCPTARGET (not checked in) has the login info, file system location
  # prefix, and associated url prefix for uploading to origin and
  # downloading via https, and it likely looks something like this:
  # SCPTARGET=who@where
  # SCPPREFIX=/var/www/whatever/
  # SCPURLBASE=https://where/whatever
  . custom/SCPTARGET.sh
  scp ${WORK}/${OUTFNAME} ${SCPTARGET}:${SCPPREFIX}chromium-builds/${CHAN}/
  ssh ${SCPTARGET} "ls -t ${SCPPREFIX}chromium-builds/${CHAN}/" | \
    tail -n +${ROTATION} | sed -e "s@\(.*\)@${SCPPREFIX}chromium-builds/${CHAN}/\1@" | \
    xargs -r ssh ${SCPTARGET} rm
  ssh ${SCPTARGET} "ls -t ${SCPPREFIX}chromium-builds/${CHAN}/" |
    sed -e "s@\(.*\)@ * ${SCPURLBASE}/chromium-builds/${CHAN}/\1@" > \
    CURRENT_BINARIES.${CHAN}.md
  mv ${WORK}/PROPOSED.${CHAN}.sh LAST_GOOD.${CHAN}.sh
  git add LAST_GOOD.${CHAN}.sh CURRENT_BINARIES.${CHAN}.md
  git commit -m "auto-updated ${CHAN} at ${STARTTIME} (LAST_GOOD from ${LAST_GOOD_TAG} to ${VER})"
fi

rm -rf $(readlink ${WORK}/bld-${CHAN})
rm ${WORK}/bld-${CHAN}
