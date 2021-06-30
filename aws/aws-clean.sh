#!/bin/bash

set -x
set -e

. aws-fix.sh

if [ "${INSTID}" != "none" ]; then
  aws --region ${REGION} ec2 terminate-instances --instance-ids ${INSTID} || true

  for i in $(seq 30); do
    sleep 10
    if aws ec2 --region ${REGION} describe-instance-status --instance-ids ${INSTID} --include-all-instances | grep -E "terminated"; then
    #if ! aws ec2 describe-instance-status --instance-ids ${INSTID} --filters Name=instance-state-code,Values=16,32,64 | grep -E "running|shutting|stopping"; then
      break
    fi
  done
fi

aws --region ${REGION} ec2 delete-security-group --group-id ${SGID}
rm ${DESCFILE}
rm ${RUNFILE}
rm ${SGFILE}

