#!/bin/bash

# call example: curl https://raw.githubusercontent.com/tonwhales/validator-monitoring/main/deploy.sh | bash -x -- --role validator

containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

service_exists() {
    local n=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
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

REPO_PREFIX=https://raw.githubusercontent.com/tonwhales/validator-monitoring/main

if ! service_exists datadog-agent; then 
  echo "Datadog package needs to be installed before deploying."
  exit
fi

# we need 1c78056a4249672a8e9eb0548c79e02d3ce19d5e
pushd /usr/src/mytonctrl; git pull origin master; popd
mkdir /usr/src/validator-monitoring/
wget -O /usr/src/validator-monitoring/common.py $REPO_PREFIX/common.py
python3 -c 'import sys; sys.path.append("/usr/src/mytonctrl"); import mytoninstaller; mytoninstaller.Init(); mytoninstaller.CreateLocalConfig(mytoninstaller.GetInitBlock(), localConfigPath="/usr/src/validator-monitoring/local.config.json")'
ENVIRONMENT=$(python3 -c 'import sys; sys.path.append("/usr/src/validator-monitoring"); import common; print(common.EnvEnrichedConsumer().get_environment())')

wget -O /etc/datadog-agent/conf.d/lite_clien_last_block_age_seconds.yaml $REPO_PREFIX/lite_clien_last_block_age_seconds.yaml
wget -O /etc/datadog-agent/checks.d/lite_clien_last_block_age_seconds.py $REPO_PREFIX/lite_clien_last_block_age_seconds.py

# nginx logs collection example
# sed -i "s@# logs_enabled: false@logs_enabled: true@g" /etc/datadog-agent/datadog.yaml
# wget -O /etc/datadog-agent/conf.d/nginx.d/conf.yaml $REPO_PREFIX/conf.d_nginx.d_conf.yaml
if [ "$ROLE" == ${ROLES[validator]} ]; then
    wget -O /opt/datadog-agent/embedded/lib/python3.8/lib-dynload/readline.cpython-38-x86_64-linux-gnu.so $REPO_PREFIX/readline.cpython-38-x86_64-linux-gnu.so
    wget -O /etc/datadog-agent/conf.d/validator_efficiency.yaml $REPO_PREFIX/validator_efficiency.yaml
    wget -O /etc/datadog-agent/checks.d/validator_efficiency.py $REPO_PREFIX/validator_efficiency.py
    wget -O /etc/datadog-agent/conf.d/ton_validation_cycles.yaml $REPO_PREFIX/ton_validation_cycles.yaml
    wget -O /etc/datadog-agent/checks.d/ton_validation_cycles.py $REPO_PREFIX/ton_validation_cycles.py
fi
rm /etc/datadog-agent/conf.d/directory.d/conf.yaml
rm /etc/datadog-agent/conf.d/var_ton_work_db_files_packages_size.yaml
rm /etc/datadog-agent/checks.d/var_ton_work_db_files_packages_size.py
sed -i 's@# process_config@process_config:\n  enabled: "true"@g' /etc/datadog-agent/datadog.yaml
sed -i 's@^process_config$@process_config:@g' /etc/datadog-agent/datadog.yaml
sed -i 's@enabled: "true":$@enabled: "true"@g' /etc/datadog-agent/datadog.yaml
sed -i "s@^# tags:@tags:\n  - environment:$ENVIRONMENT\n  - role:$ROLE@g" /etc/datadog-agent/datadog.yaml


wget -O /usr/src/validator-monitoring/ton_db_size.py $REPO_PREFIX/ton_db_size.py
wget -O /etc/systemd/system/ton-db-size.service $REPO_PREFIX/ton-db-size.service
systemctl daemon-reload
systemctl enable ton-db-size
systemctl start ton-db-size
systemctl restart ton-db-size
wget -O /etc/datadog-agent/checks.d/ton_db_size.py $REPO_PREFIX/check.d_ton_db_size.py
wget -O /etc/datadog-agent/conf.d/ton_db_size.yaml $REPO_PREFIX/ton_db_size.yaml
systemctl restart datadog-agent
