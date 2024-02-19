#!/bin/bash

set -eux -o pipefail

# call example: curl https://raw.githubusercontent.com/tonwhales/validator-monitoring/main/deploy.sh | bash -x -- --role validator

containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

declare -A ROLES
ROLES[validator]="validator"
ROLES[archive]="archive"
ROLES[dev]="dev"

while [[ $# -gt 0 ]]; do
  case $1 in
    --role)
      if ! containsElement "$2" "${ROLES[@]}"; then
          echo "Cannot proceed without knowing role."
          exit 1
      fi
      ROLE="$2"
      shift
      shift
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

REPO_PREFIX=https://raw.githubusercontent.com/tonwhales/validator-monitoring/master

if [ ! -f /etc/default/grafana-agent ]; then
    echo "Please, deploy params first!"
    exit
fi

# we need 1c78056a4249672a8e9eb0548c79e02d3ce19d5e
pushd /usr/src/mytonctrl
if ! git cat-file -e 1c78056a4249672a8e9eb0548c79e02d3ce19d5e; then
    echo "mytonctrl must have commit with id 1c78056a4249672a8e9eb0548c79e02d3ce19d5e for this script to work properly"
    exit
fi
popd
mkdir /usr/src/validator-monitoring/
wget -O /usr/src/validator-monitoring/common.py $REPO_PREFIX/common.py
python3 -c 'import sys; sys.path.append("/usr/src/mytonctrl"); import mytoninstaller; mytoninstaller.Init(); mytoninstaller.CreateLocalConfig(mytoninstaller.GetInitBlock(), localConfigPath="/usr/src/validator-monitoring/local.config.json")'
ENVIRONMENT=$(python3 -c 'import sys; sys.path.append("/usr/src/validator-monitoring"); import common; print(common.get_environment())')

sed -i "s@__PLACE_ENV_HERE__@$ENVIRONMENT@g" /etc/default/grafana-agent
sed -i "s@__PLACE_ROLE_HERE__@$ROLE@g" /etc/default/grafana-agent

apt -y install python3-prometheus-client
ARCH=amd64
RELEASE_VERSION=$(basename $(curl -Ls -o /dev/null https://github.com/grafana/agent/releases/latest -w %{url_effective}) | tr -d "v")
RELEASE_URL="https://github.com/grafana/agent/releases/download/v${RELEASE_VERSION}"
DEB_URL="${RELEASE_URL}/grafana-agent-${RELEASE_VERSION}-1.${ARCH}.deb"
curl -fL# "${DEB_URL}" -o /tmp/grafana-agent.deb || fatal 'Failed to download package'
dpkg --force-confold -i /tmp/grafana-agent.deb
rm /tmp/grafana-agent.deb

wget -O /etc/systemd/system/ton-exporter.service $REPO_PREFIX/ton-exporter.service
wget -O /usr/src/validator-monitoring/ton-exporter.py $REPO_PREFIX/ton-exporter.py
wget -O /etc/grafana-agent.yaml $REPO_PREFIX/grafana-agent.yaml

systemctl daemon-reload
systemctl enable ton-exporter
systemctl start ton-exporter
systemctl restart ton-exporter
systemctl enable grafana-agent
systemctl start grafana-agent
systemctl restart grafana-agent

if [ "$ROLE" == ${ROLES[validator]} ]; then
    mkdir -p /etc/etcd-registrar/
    wget -O /etc/etcd-registrar/config.values $REPO_PREFIX/config.values
    apt -y install jq
    PORT=$(jq ".control | .[].port" /var/ton-work/db/config.json)
    sed -i "s@__PLACE_PORT_HERE__@$PORT@g" /etc/etcd-registrar/config.values
    sed -i "s@__PLACE_ENV_HERE__@$ENVIRONMENT@g" /etc/etcd-registrar/config.values
    if [ ! -f /etc/etcd-registrar/config.secrets ]; then
        echo "PLEASE, DEPLOY SECRETS FIRST!"
        exit 1
    fi
    apt install -y software-properties-common
    add-apt-repository --yes ppa:yma-het/etcd-client
    apt install -y etcd-registrar

fi
