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
else
  BRANCH="manual-VER-${VER}-no-BRANCH"
fi

. LAST_GOOD.${CHAN}.sh

if [ "${LAST_GOOD_DIFF_URL}" != "" -a "${LAST_GOOD_DIFF_FILE}" != "" ]; then
  echo "$(date) both LAST_GOOD_DIFF_FILE (${LAST_GOOD_DIFF_FILE}) and LAST_GOOD_DIFF_URL (${LAST_GOOD_DIFF_URL}) are set, please unset one" | tee -a ${LOGF}
  exit 1
fi

if [ "${LAST_GOOD_DIFF_URL}" != "" ]; then
  LAST_GOOD_DIFF_FILE=${WORK}/patch.diff
  if ! curl -q -f -s "${LAST_GOOD_DIFF_URL}" > "${LAST_GOOD_DIFF_FILE}" ; then
    echo "$(date) failed curl of ${LAST_GOOD_DIFF_URL} to pull last good diff to ${LAST_GOOD_DIFF_FILE}" | tee -a ${LOGF}
    exit 1
  fi
fi

if [ "${LAST_GOOD_DIFF_FILE}" != "" -a ! -f "${LAST_GOOD_DIFF_FILE}" ]; then
    echo "$(date) no such file LAST_GOOD_DIFF_FILE=${LAST_GOOD_DIFF_FILE} (from LAST_GOOD.${CHAN}.sh" | tee -a ${LOGF}
    exit 1
fi

ABS_LAST_GOOD_DIFF=$(python -c "from os.path import abspath; print(abspath('${LAST_GOOD_DIFF_FILE}'))")
CUR_SHA256=$(shasum -a 256 ${LAST_GOOD_DIFF_FILE} | awk '{print $1;}')

if [ "${CUR_SHA256}" = "${LAST_GOOD_DIFF_SHA256}" -a "${LAST_GOOD_TAG}" = "${VER}" -a "${LAST_GOOD_BRANCH}" = "${BRANCH}" ]; then
    echo "$(date) chromium channel=${CHAN} is unchanged from last good: VER=${VER}, BRANCH=${BRANCH}" | tee -a ${LOGF}
    exit 1
fi

echo "${CHAN} build ${VER} start at $(date)" | tee -a ${LOGF}

echo "LAST_GOOD_TAG=${VER}" > ${WORK}/PROPOSED.${CHAN}.sh
if [ "${LAST_GOOD_DIFF_URL}" != "" ]; then
  echo "LAST_GOOD_DIFF_URL=\"${LAST_GOOD_DIFF_URL}\"" >> ${WORK}/PROPOSED.${CHAN}.sh
  echo "#LAST_GOOD_DIFF_FILE=" >> ${WORK}/PROPOSED.${CHAN}.sh
else
  echo "#LAST_GOOD_DIFF_URL=" >> ${WORK}/PROPOSED.${CHAN}.sh
  echo "LAST_GOOD_DIFF_FILE=\"${LAST_GOOD_DIFF_FILE}\"" >> ${WORK}/PROPOSED.${CHAN}.sh
fi
echo "LAST_GOOD_DIFF_SHA256=${CUR_SHA256}" >> ${WORK}/PROPOSED.${CHAN}.sh
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
#cat Dockerfile.base \
#  | sed -e "s@PATCHFILE@${LAST_GOOD_DIFF_FILE}@" \
#  | sed -e "s@PROPOSEDFILE@${WORK}/PROPOSED.${CHAN}.sh@" \
#  > ${WORK}/Dockerfile.${CHAN}.latest
#${DKR} build --file ${WORK}/Dockerfile.${CHAN}.latest --tag ${CI}:latest .
${DKR} build --file Dockerfile \
  --build-arg USER_ID=$(id -u ${USER}) \
  --build-arg GROUP_ID=$(id -g ${USER}) \
  --build-arg PATCHFILE=${LAST_GOOD_DIFF_FILE} \
  --tag ${CI}:latest .

BLDDIR=$(mktemp -d -t chrome-build-XXXXXX)
rm -f ${WORK}/bld-${CHAN}
ln -s ${BLDDIR} ${WORK}/bld-${CHAN}

# NB: the snap socket is needed for snapcraft during build-dependencies.
# Note # also there exists docker setups able to run snaps, e.g.:
# https://github.com/ogra1/snapd-docker/blob/master/build.sh, however it
# seems to need a different entrypoint that's less convenient for my usage,
# so I do it this way, which uses the host's snap socket. --jake 2021-03-20
${DKR} run --name ${CN} -it \
	--env VERSION=${VER} \
	--env LASTGOOD=${LAST_GOOD_TAG} \
	--env CHAN=${CHAN} \
	--env PATCHFILE=/tmp/patch.diff \
  -v ${BLDDIR}:/bld \
	-v /run/snapd.socket:/run/snapd.socket ${CI}:latest

# docker cp ${CN}:where-the-.deb-is .
#${DKR} cp ${CN}:/bld/src/out/Default/chromium-browser-mc-unstable_${VER}-1_amd64.deb ${WORK}/
cp ${WORK}/bld/src/out/Default/chromium-browser-mc-unstable_${VER}-1_amd64.deb ${WORK}

mv ${WORK}/PROPOSED.${CHAN}.sh LAST_GOOD.${CHAN}.sh

# ${DKR} rm ${CN}
${DKR} image prune -f

git add LAST_GOOD.${CHAN}.sh
git commit -m "auto-updated ${CHAN} at ${STARTTIME} from ${LAST_GOOD_TAG} to ${VER}"

. SCPTARGET.sh
scp ${WORK}/chromium-browser-mc-unstable_${VER}-1_amd64.deb ${SCPTARGET}

#sudo dpkg --remove chromium-browser-mc-unstable
#sudo dpkg --install ./chromium-browser-unstable_90.0.4430.11+multicast-1_amd64.deb


