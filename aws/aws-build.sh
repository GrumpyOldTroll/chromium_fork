#!/bin/bash

# standalone script to build a specific version on AWS

set -e

echo 'setting startup to defaults if env unset:'
set -x

DISKSIZE=${DISKSIZE:-'100'}
# 50 not enough

REGION=${REGION:-'us-west-1'}
# free tier (t3.micro) does not work.  always fails, I think needs more memory.
INSTTYPE=${INSTTYPE:-'c5.2xlarge'}
KEEP=${KEEP:-'0'}
KEYPAIR=${KEYPAIR:-$(aws --region ${REGION} ec2 describe-key-pairs --query "KeyPairs[:1].KeyName" --output text)}

AMI=${AMI:-$(aws --region ${REGION} ec2 describe-images \
    --owners 099720109477 \
    --filters \
        "Name=state,Values=available" \
        "Name=architecture,Values=x86_64" \
        "Name=root-device-type,Values=ebs" \
        "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" \
    --query "reverse(sort_by(Images,&CreationDate))[:1].ImageId" \
    --output text)}

CHAN=${CHAN:-'stable'}
VER=${VER:-$(curl -s -q -f https://raw.githubusercontent.com/GrumpyOldTroll/chromium_fork/main/LAST_GOOD.${CHAN}.sh | grep LAST_GOOD_TAG | cut -f2 -d=)}

NOW=$(date +"%Y%m%d-%H%M%S")
TEMPBASE="aws-cbuild-XXX-${NOW}.json"
SGFILE=$(mktemp -t "sg-${TEMPBASE}")

aws --region ${REGION} ec2 create-security-group \
  --description "SSH+PING" \
  --group-name "cbuild-sg-${NOW}" > ${SGFILE}
SGID=$(python3 -c "import json; v=json.load(open('${SGFILE}')); print(v['GroupId'])")

aws --region ${REGION} ec2 authorize-security-group-ingress \
  --group-id ${SGID} \
  --ip-permissions "IpProtocol=tcp,IpRanges=[{CidrIp=0.0.0.0/0,Description=SSH}],Ipv6Ranges=[{CidrIpv6=::/0,Description=SSH}],ToPort=22,FromPort=22"
aws --region ${REGION} ec2 authorize-security-group-ingress \
  --group-id ${SGID} \
  --ip-permissions "IpProtocol=icmp,IpRanges=[{CidrIp=0.0.0.0/0,Description=PING}],ToPort=-1,FromPort=-1"
aws --region ${REGION} ec2 authorize-security-group-ingress \
  --group-id ${SGID} \
  --ip-permissions "IpProtocol=icmpv6,Ipv6Ranges=[{CidrIpv6=::/0,Description=PING6}],ToPort=-1,FromPort=-1"

RUNFILE=$(mktemp -t "run-${TEMPBASE}")
aws --region ${REGION} ec2 run-instances \
  --image-id ${AMI} \
  --instance-type ${INSTTYPE} \
  --key-name ${KEYPAIR} \
  --security-group-ids "${SGID}" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={DeleteOnTermination=true,VolumeSize=${DISKSIZE}}" \
  --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=cbuild-inst-${NOW}}]" \
      "ResourceType=volume,Tags=[{Key=Name,Value=cbuild-disk-${NOW}}]" \
  --count 1 \
  > ${RUNFILE}

INSTID=$(python3 -c "import json; v=json.load(open('${RUNFILE}')); print(v['Instances'][0]['InstanceId'])")
sleep 1

for i in $(seq 20); do
  sleep 5
  if aws --region ${REGION} ec2 describe-instance-status --instance-ids ${INSTID} --filters Name=instance-state-code,Values=16 | grep running; then
    break
  fi
done

DESCFILE=$(mktemp -t "desc-${TEMPBASE}")
aws --region ${REGION} ec2 describe-instances --instance-ids ${INSTID} > ${DESCFILE}
INSTHOST=$(python3 -c "import json; v=json.load(open('${DESCFILE}')); print(v['Reservations'][0]['Instances'][0]['PublicDnsName'])")
SSHC='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l ubuntu'

for i in $(seq 30); do
  if ${SSHC} -o ConnectTimeout=3 ${INSTHOST} "true"; then
    break
  fi
  sleep 3
done

# sometime the apt-get update fails if you're too early
sleep 5

${SSHC} ${INSTHOST} <<EOF
set -x
set -e
sudo apt-get update
sudo apt-get dist-upgrade -y
sudo apt-get install -y docker.io screen snapd git python3 python-is-python3
sudo usermod -aG docker ubuntu
sudo snap install jq
git clone https://github.com/GrumpyOldTroll/chromium_fork/
EOF
${SSHC} ${INSTHOST} <<EOF
set -x
set -e
cd chromium_fork
mkdir nightly-build/
sed -i LAST_GOOD.${CHAN}.sh -e 's/LAST_GOOD_TAG=.*/LAST_GOOD_TAG=none/'
touch screen.${CHAN}.log
screen -d -L -Logfile screen.${CHAN}.log -m /bin/bash -c "CHAN=${CHAN} VER=${VER} ./nightly.sh ; exit"
EOF
${SSHC} ${INSTHOST} "( while ! ls chromium_fork/nightly-junk/bld-${CHAN}/src/out/Default/*.deb 2>/dev/null; do sleep 60; done; killall tail ) & tail -f chromium_fork/screen.${CHAN}.log"

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${INSTHOST}:chromium_fork/nightly-junk/chromium-browser-mc-unstable_${VER}-1_amd64.deb .

if [ ${KEEP} != "0" ]; then
  aws --region ${REGION} ec2 terminate-instances --instance-ids ${INSTID} || true

  for i in $(seq 30); do
    sleep 10
    if aws ec2 --region ${REGION} describe-instance-status --instance-ids ${INSTID} --include-all-instances | grep -E "terminated"; then
    #if ! aws ec2 describe-instance-status --instance-ids ${INSTID} --filters Name=instance-state-code,Values=16,32,64 | grep -E "running|shutting|stopping"; then
      break
    fi
  done

  aws --region ${REGION} ec2 delete-security-group --group-id ${SGID}
  rm ${DESCFILE}
  rm ${RUNFILE}
  rm ${SGFILE}
fi
