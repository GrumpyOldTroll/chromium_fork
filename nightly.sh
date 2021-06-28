#!/bin/bash

set -e

if [ "${CHAN}" = "" ]; then
    CHAN=dev
fi

WORK=nightly-junk
mkdir -p ${WORK}
LOGF=${WORK}/chrome-build-nightly.${CHAN}.log
if [ -f ${LOGF} ]; then
  # by default keep 3 weeks of logs (losing a few days while manually checking)
  python -c "from logging.handlers import RotatingFileHandler as rf; rf('${LOGF}', backupCount=12).doRollover()"
fi

# from https://stackoverflow.com/a/22373735/3427357
#exec > /tmp/out.log 2>&1

CN=cbuild-${CHAN}
CI=${CN}
DKR=docker

STOP=0
if ! ${DKR} container ls 2> /dev/null 1> /dev/null ; then
  echo "$(date) error: '${DKR} container ls' failed, check docker install (USER=${USER})" | tee -a ${LOGF}
  STOP=1
fi
if ! which jq 2> /dev/null 1> /dev/null ; then
  echo "$(date) error: 'which jq' had no jq installed" | tee -a ${LOGF}
  STOP=1
fi
if ! which snap 2> /dev/null 1> /dev/null ; then
  echo "$(date) error: 'which snap' had no snapd installed" | tee -a ${LOGF}
  STOP=1
fi
if [ "${STOP}" != "0" ]; then
  exit 1
fi

CLEANED_REPORT=""
if ${DKR} container inspect ${CN} 2> /dev/null 1> /dev/null ; then
  PREV_RUNNING=$(${DKR} container inspect ${CN} 2> /dev/null | jq -r ".[].State.Running")
  if [ "${PREV_RUNNING}" != "true" -a "${PREV_RUNNING}" != "false" ]; then
      echo "$(date) error: docker container ${CN} could not determine prior running state" | tee -a ${LOGF}
      exit 1
  fi

  if [ "${PREV_RUNNING}" = "true" ]; then
      echo "$(date) docker container ${CN} already running" | tee -a ${LOGF}
      exit 1
  fi

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
else
  echo "$(date) docker container ${CN} not present, proceeding" | tee -a ${LOGF}
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
  DIFFDESC="${LAST_GOOD_DIFF_SPEC}"
  DIFFADVICE="Please push local commits to LAST_GOOD.${CHAN}.sh and CURRENT_BINARIES.${CHAN}.md"
else
  cat Dockerfile.base \
    | sed -e "s@PATCH_LINE1@ENV PATCHFILE=\"/tmp/patch.diff\"@" \
    | sed -e "s@PATCH_LINE2@COPY ${LAST_GOOD_DIFF_FILE} /tmp/patch.diff@" \
    > ${WORK}/Dockerfile.${CHAN}
  DIFFDESC="${LAST_GOOD_DIFF_FILE} (a local patch)"
  DIFFADVICE="Please wrap up the patch generation process from https://github.com/GrumpyOldTroll/chromium_fork#building-a-patch with a diff between checked-in tags"
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
#
# PS: we run with -i instead of -d so that we can get in interactively
# afterwards if it goes wrong.  We do it in screen so it'll have an input
# terminal.
/usr/bin/screen -d -m /bin/bash -c "${DKR} run --name ${CN} -it \
	--env VERSION=${VER} \
	--env LASTGOOD=${LAST_GOOD_TAG} \
	--env CHAN=${CHAN} \
  -v ${BLDDIR}:/bld \
	-v /run/snapd.socket:/run/snapd.socket ${CI}:latest"

sleep 2
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
  DEB=${WORK}/${OUTFNAME} CHAN=${CHAN} ./rotate.sh
  echo "export CHAN=${CHAN}" > ${WORK}/rot-${CHAN}.sh
  echo "export DEB=${WORK}/${OUTFNAME}" >> ${WORK}/rot-${CHAN}.sh

  mv ${WORK}/PROPOSED.${CHAN}.sh LAST_GOOD.${CHAN}.sh
  git add LAST_GOOD.${CHAN}.sh
  git commit -m "auto-updated ${CHAN} at ${STARTTIME} (LAST_GOOD from ${LAST_GOOD_TAG} to ${VER})"
fi

rm -rf $(readlink ${WORK}/bld-${CHAN})
rm ${WORK}/bld-${CHAN}
echo "SUCCESS($(date +"%Y-%m-%d %H:%M:%S")): build changed from ${LAST_GOOD_TAG} to ${VER} with diff=${DIFFDESC}"
echo "${DIFFADVICE}"
exit 2
