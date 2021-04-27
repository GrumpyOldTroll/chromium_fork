#!/bin/bash

set -e

# You need a few files under custom/:
# - CUSTOM.sh:
#    TOMAIL=someone@example.com
#    LOCATION=/home/someone/chromium_fork
# - SCPTARGET.sh:
#    SCPTARGET=someone@backend-host.example.com
#    SCPURLBASE=https://frontend-download-loc.example.com/somewhere
#    SCPPREFIX=/var/www/somewhere/
# - template-pass.txt
# - template-fail.txt

. custom/CUSTOM.sh
cd ${LOCATION}

export CHAN=dev
if ./nightly.sh > nightly-junk/full-${CHAN}.txt 2>&1; then
  DEVRESULT=1
else
  DEVRESULT=0
fi

export CHAN=stable
if ./nightly.sh > nightly-junk/full-${CHAN}.txt 2>&1; then
  STABLERESULT=1
else
  STABLERESULT=0
fi

MSG=nightly-junk/msg.txt

if [ "${DEVRESULT}" = "1" -a "${STABLERESULT}" = "1" ]; then
  cp custom/template-pass.txt ${MSG}
  mutt -s "PASS both chromium builds ($(date +'%Y-%m-%d %H:%M:%S'))" ${TOMAIL} < ${MSG}
elif [ "${DEVRESULT}" = "0" -a "${STABLERESULT}" = "0" ]; then
  cp custom/template-fail.txt ${MSG}
  echo "" >> ${MSG}
  echo "---------------------------------------- dev -----------------------------------------------" >> ${MSG}
  echo "" >> ${MSG}
  echo "tail -n 200 nightly-junk/chrome-build-nightly.dev.log" >> ${MSG}
  tail -n 200 nightly-junk/chrome-build-nightly.dev.log >> ${MSG}
  echo "" >> ${MSG}
  echo "----------------------- stable ---------------------------" >> ${MSG}
  echo "" >> ${MSG}
  echo "tail -n 200 nightly-junk/chrome-build-nightly.stable.log" >> ${MSG}
  tail -n 200 nightly-junk/chrome-build-nightly.stable.log >> ${MSG}
  mutt -s "FAIL chromium build (both) ($(date +'%Y-%m-%d %H:%M:%S'))" ${TOMAIL} < ${MSG}
else
  if [ "${DEVRESULT}" = "0" ]; then
    WHICH=dev
  else
    WHICH=stable
  fi
  cp custom/template-fail.txt ${MSG}
  echo "" >> ${MSG}
  echo "------------------------ ${WHICH} -----------------------------" >> ${MSG}
  echo "" >> ${MSG}
  echo "tail -n 200 nightly-junk/chrome-build-nightly.${WHICH}.log" >> ${MSG}
  tail -n 200 nightly-junk/chrome-build-nightly.${WHICH}.log >> ${MSG}
  mutt -s "FAIL chromium build (${WHICH}) ($(date +'%Y-%m-%d %H:%M:%S'))" ${TOMAIL} < ${MSG}
fi
