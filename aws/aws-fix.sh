REGION=${REGION:-'us-west-1'}
CHAN=${CHAN:-'stable'}
TDF=$(mktemp -t cb-fix-XXXXX)
TD=$(dirname ${TDF})
rm ${TDF}
SGFILE=$(ls -t ${TD}/sg-aws-cbuild-* | head -n 1)
TSTAMP=$(echo $(basename ${SGFILE}) | rev | cut -d- -f1-2 | rev)
SGID=$(python3 -c "import json; v=json.load(open('${SGFILE}')); print(v['GroupId'])")
RUNFILE=$(ls -t ${TD}/run-aws-cbuild-*-${TSTAMP} | head -n 1)
INSTID=$(python3 -c "import json; v=json.load(open('${RUNFILE}')); print(v['Instances'][0]['InstanceId'])" || echo 'none')
DESCFILE=$(ls -t ${TD}/desc-aws-cbuild-*-${TSTAMP} | head -n 1)
INSTHOST=$(python3 -c "import json; v=json.load(open('${DESCFILE}')); print(v['Reservations'][0]['Instances'][0]['PublicDnsName'])" || echo 'none')

SSHC='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l ubuntu'
