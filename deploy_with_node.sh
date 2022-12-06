#!/bin/bash

set -eux -o pipefail

SECRET=""
HOST_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --secret)
      SECRET="$2"
      shift
      shift
      ;;
    --hostname)
      HOST_NAME="$2"
      shift
      shift
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

if [[ -z "${SECRET// }" ]]; then
    echo "Secret variable cannot be empty."
    exit 1
fi
if [[ -z "${HOST_NAME// }" ]]; then
    echo "Secret variable cannot be empty."
    exit 1
fi
if [ "$EUID" -ne 0 ]
  then echo "This script must be run as root"
  exit 1
fi



# Check HW suitability
apt install -y fio jq
READ_IOPS_PREQUIRED=700
WRITE_IOPS_REQUIRED=200
HT_REQUIRED=8
MEM_REQUIRED=63   # rounding error must be tolerated
SPACE_REQUIRED=800
ERROR_COMMON_MESSAGE="Validator engine cannot effectively work on"
OVERALL_THREADS=$(lscpu --json | jq '(.lscpu[] | select(.field=="CPU(s):") | .data | tonumber) * (.lscpu[] | select(.field=="Thread(s) per core:") | .data | tonumber)')
if [ $OVERALL_THREADS -lt $HT_REQUIRED ]; then
    echo $ERROR_COMMON_MESSAGE "nodes with less than $HT_REQUIRED hyperthreads. Got $OVERALL_THREADS instead."
    exit 1
fi
OVERALL_MEM=$(cat /proc/meminfo | numfmt --field 2 --from-unit=Ki --to-unit=Gi | sed 's/ kB//g' | grep MemTotal | sed "s@MemTotal:[ \t]*@@g")
if [ $OVERALL_MEM -lt $MEM_REQUIRED ]; then
    echo $ERROR_COMMON_MESSAGE "nodes with less than $MEM_REQUIRED Gb of RAM. Got $OVERALL_MEM instead."
    exit 1
fi
BENCH_RESULT=$(fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=1M --iodepth=$OVERALL_THREADS --size=4G --readwrite=randrw --rwmixread=75  --output-format=json | jq '.jobs[] | {write: .write.iops | round, read: .read.iops | round}')
rm -f test
READ_IOPS=$(echo $BENCH_RESULT | jq '.read')
WRITE_IOPS=$(echo $BENCH_RESULT | jq '.write')
if [ $READ_IOPS -lt $READ_IOPS_PREQUIRED ]; then
    echo $ERROR_COMMON_MESSAGE "disks/arrays with less than $READ_IOPS_PREQUIRED IOPs with 1M blocks for read. Got $READ_IOPS instaed."
    exit 1
fi
if [ $WRITE_IOPS -lt $WRITE_IOPS_REQUIRED ]; then
    echo $ERROR_COMMON_MESSAGE "disks/arrays with less than $READ_IOPS_PREQUIRED IOPs with 1M blocks for write. Got WRITE_IOPS instead."
    exit 1
fi

if [ $(grep PermitRootLogin /etc/ssh/sshd_config | grep yes | wc -l) -ne 0 ]; then
    echo "Secyrity policies does not allow sshd with pwauth enabled. Please disable it anr restart sshd resrvice to apply new config."
    exit 1
fi

if [ $(grep $HOST_NAME /etc/hostname | wc -l) -lt 1 ]; then
    echo "Please adjust your hostname to match $HOST_NAME"
    exit 1
fi
if [ $(grep $HOST_NAME /etc/hosts | wc -l) -lt 1 ]; then
    echo "Please adjust your /etc/hosts so at least one record matches $HOST_NAME"
    exit 1
fi

FREE_ON_VAR=$(df | grep $(findmnt -n -o SOURCE --target /var) |  awk '{print $4}' | numfmt --from-unit=Ki --to-unit=Gi)
if [ $FREE_ON_VAR -le $SPACE_REQUIRED ]; then
    echo "Mountpoint /var has only $FREE_ON_VAR Gb, but validator requires at least $SPACE_REQUIRED Gb."
    exit 1
fi



# Install validator and configure it
curl https://raw.githubusercontent.com/ton-blockchain/mytonctrl/master/scripts/install.sh | bash -eux -s -- -t -m full
systemctl stop validator
systemctl stop mytoncore
sed -i "s@--state-ttl 604800 --archive-ttl 1209600 --verbosity 1@--state-ttl 259200 --archive-ttl 604800 --verbosity 3@"
systemctl daemon-reload
apt -y install plzip jq vim
mv /var/ton-work/db /var/ton-work/db-old
wget -q --show-progress https://dump.ton.org/dumps/latest.tar.lz
sudo mkdir /var/ton-work/db
mv latest.tar.lz /var/ton-work/db/
cd /var/ton-work/db/
plzip -cd latest.tar.lz | tar -xf -
cp -r /var/ton-work/db-old/keyring /var/ton-work/db/
cp /var/ton-work/db-old/config.json /var/ton-work/db/
rm latest.tar.lz
sudo chown -R validator:validator .
systemctl start validator
systemctl start mytoncore
sleep 50
while [ $(python3 -c 'import sys; sys.path.append("/usr/src/mytonctrl"); import mytoncore; c = 1000; c = mytoncore.MyTonCore().GetValidatorStatus().get("outOfSync"); print(c)') -gt 10 ]; do
    sleep 10
    echo "wating full sync..."
done


# Setup minotorings
mkdir -p /etc/etcd-registrar/; echo $SECRET | base64 -d |  openssl zlib -d | jq ".etcd_config" -r | base64 -d > /etc/etcd-registrar/config.secrets
echo $SECRET | base64 -d |  openssl zlib -d | jq ".grafana_agent_config" -r | base64 -d > /etc/default/grafana-agent
curl https://raw.githubusercontent.com/tonwhales/validator-monitoring/grafana/deploy.sh  | bash -eux -s -- --role validator
apt install -y vim jq
echo "Copy this text and send it back to whales:"
echo -en '        {\n            "clientSecret": "'; base64 /var/ton-work/keys/client | tr -d "\n"; echo -en '",\n            "serverPublic": "'; base64 /var/ton-work/keys/server.pub | tr -d "\n"; echo -en '",\n            "endpoint": "'; ip a | grep "/32" | sed "s@    inet @@g" | sed "s@/32 scope.*@@g" | tr -d "\n"; echo -n ":"; jq -r ".control | .[].port" /var/ton-work/db/config.json | tr -d "\n"; echo -en '",\n            "adnl": "'; mytonctrl <<< status 2>&1 | grep -v "\[debug\]\|\[warning\]\|\[info\]\|Welcome to the console\|Bye" | grep "ADNL address of local validator" | sed "s@ADNL address of local validator: @@g"| tr -d "\n" ; echo -e '"\n        }'