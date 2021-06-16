#!/bin/bash

if [ "${CHAN}" = "" ]; then
  echo "CHAN unset in rotate.sh"
  exit 1
fi

if [ "${DEB}" = "" ]; then
  echo "DEB unset in rotate.sh"
  exit 1
fi

set -e
set -x

ROTATION=10
# SCPTARGET (not checked in) has the login info, file system location
# prefix, and associated url prefix for uploading to origin and
# downloading via https, and it likely looks something like this:
# SCPTARGET=who@where
# SCPPREFIX=/var/www/whatever/
# SCPURLBASE=https://where/whatever
. custom/SCPTARGET.sh
/usr/bin/scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSHKEY} ${DEB} ${SCPTARGET}:${SCPPREFIX}chromium-builds/${CHAN}/
/usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSHKEY} ${SCPTARGET} "ls -t ${SCPPREFIX}chromium-builds/${CHAN}/" | \
  /usr/bin/tail -n +$((${ROTATION}+4)) | /bin/sed -e "s@\(.*\)@${SCPPREFIX}chromium-builds/${CHAN}/\1@" | \
  /usr/bin/xargs -r ssh ${SCPTARGET} rm
/usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSHKEY} ${SCPTARGET} "ls -t ${SCPPREFIX}chromium-builds/${CHAN}/" | \
  /bin/sed -e "s@\(.*\)@ * ${SCPURLBASE}/chromium-builds/${CHAN}/\1@" | \
  /usr/bin/head -n ${ROTATION} > CURRENT_BINARIES.${CHAN}.md

# sometimes on a bad ssh the CURRENT_BINARIES winds up empty, don't commit those.
BINCHECK=$(wc -l CURRENT_BINARIES.${CHAN}.md | awk '{print $1;}')
if [ "${BINCHECK}" != "0" ]; then
  /usr/bin/git add CURRENT_BINARIES.${CHAN}.md
fi

