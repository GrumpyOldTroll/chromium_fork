#!/bin/bash

set -e

# You need a few files under custom/:
# - CUSTOM.sh:
#    export TOMAIL=someone@example.com
#    export LOCATION=/home/someone/chromium_fork
# - SCPTARGET.sh:
#    SCPTARGET=someone@backend-host.example.com
#    SCPURLBASE=https://frontend-download-loc.example.com/somewhere
#    SCPPREFIX=/var/www/somewhere/
# - template-unchanged.txt (for if the upstream release tags didn't move)
# - template-pass.txt (for if the build passed)
# - template-fail.txt (for a build failure)

# 11 13 * * * /bin/bash -c '. /home/jholland/src/chromium_fork/custom/CUSTOM.sh ; cd ${LOCATION} ; ./chromium-build-cron.sh'

#. custom/CUSTOM.sh
#cd ${LOCATION}

MSG=nightly-junk/msg.txt
echo "" > ${MSG}
ATTENTION=0
CHANNELS=0
for rel in dev stable; do
  export CHAN=${rel}
  echo "" >> ${MSG}
  echo "---------------------------------------- ${CHAN} -----------------------------------------------" >> ${MSG}
  echo "" >> ${MSG}
  CHANNELS=$((CHANNELS+1))
  # if ./nightly.sh > nightly-junk/full-${CHAN}.txt 2>&1; then
  ./nightly.sh > /dev/null 2>&1
  RET=$?
  if [ "${RET}" = "0" ]; then
    cat custom/template-unchanged.txt >> ${MSG}
    tail -n 200 nightly-junk/chrome-build-nightly.${CHAN}.log >> ${MSG}
  elif [ "${RET}" = "2" ]; then
    cat custom/template-pass.txt >> ${MSG}
    # last 2 lines of a successful nightly.sh are geared to successful build
    echo " ------ " >> ${MSG}
    tail -n 5 nightly-junk/chrome-build-nightly.${CHAN}.log >> ${MSG}
    ATTENTION=$((ATTENTION + 1))
  else
    cat custom/template-fail.txt >> ${MSG}
    echo " ------ " >> ${MSG}
    tail -n 200 nightly-junk/chrome-build-nightly.${CHAN}.log >> ${MSG}
    ATTENTION=$((ATTENTION + 1))
  fi
done

if [ "${ATTENTION}" = "0" ]; then
  mutt -s "Chromium unchanged ($(date +'%Y-%m-%d %H:%M:%S'))" ${TOMAIL} < ${MSG}
else
  mutt -s "Chromium: ${ATTENTION}/${CHANNELS} builds need attention ($(date +'%Y-%m-%d %H:%M:%S'))" ${TOMAIL} < ${MSG}
fi

