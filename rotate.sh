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
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSHKEY} ${DEB} ${SCPTARGET}:${SCPPREFIX}chromium-builds/${CHAN}/
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSHKEY} ${SCPTARGET} "ls -t ${SCPPREFIX}chromium-builds/${CHAN}/" | \
  tail -n +$((${ROTATION}+4)) | sed -e "s@\(.*\)@${SCPPREFIX}chromium-builds/${CHAN}/\1@" | \
  xargs -r ssh ${SCPTARGET} rm
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSHKEY} ${SCPTARGET} "ls -t ${SCPPREFIX}chromium-builds/${CHAN}/" | \
  sed -e "s@\(.*\)@ * ${SCPURLBASE}/chromium-builds/${CHAN}/\1@" | \
  head -n ${ROTATION} > CURRENT_BINARIES.${CHAN}.md

# sometimes on a bad ssh the CURRENT_BINARIES winds up empty, don't commit those.
BINCHECK=$(wc -l CURRENT_BINARIES.${CHAN}.md | awk '{print $1;}')
if [ "${BINCHECK}" != "0" ]; then
  git add CURRENT_BINARIES.${CHAN}.md
fi

