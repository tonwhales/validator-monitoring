#!/bin/bash

REPO_PREFIX=https://raw.githubusercontent.com/tonwhales/validator-monitoring/main

# we need 1c78056a4249672a8e9eb0548c79e02d3ce19d5e
pushd /usr/src/mytonctrl; git pull origin master; popd
mkdir /usr/src/validator-monitoring/
wget -O /usr/src/validator-monitoring/common.py $REPO_PREFIX/common.py
python3 -c 'import sys; sys.path.append("/usr/src/mytonctrl"); import mytoninstaller; mytoninstaller.Init(); mytoninstaller.CreateLocalConfig(mytoninstaller.GetInitBlock(), localConfigPath="/usr/src/validator-monitoring/local.config.json")'

wget -O /etc/datadog-agent/conf.d/lite_clien_last_block_age_seconds.yaml $REPO_PREFIX/lite_clien_last_block_age_seconds.yaml
wget -O /etc/datadog-agent/checks.d/lite_clien_last_block_age_seconds.py $REPO_PREFIX/lite_clien_last_block_age_seconds.py
wget -O /opt/datadog-agent/embedded/lib/python3.8/lib-dynload/readline.cpython-38-x86_64-linux-gnu.so $REPO_PREFIX/readline.cpython-38-x86_64-linux-gnu.so
wget -O /etc/datadog-agent/conf.d/validator_efficiency.yaml $REPO_PREFIX/validator_efficiency.yaml
wget -O /etc/datadog-agent/checks.d/validator_efficiency.py $REPO_PREFIX/validator_efficiency.py
wget -O /etc/datadog-agent/conf.d/ton_validation_cycles.yaml $REPO_PREFIX/ton_validation_cycles.yaml
wget -O /etc/datadog-agent/checks.d/ton_validation_cycles.py $REPO_PREFIX/ton_validation_cycles.py
rm /etc/datadog-agent/conf.d/directory.d/conf.yaml
rm /etc/datadog-agent/conf.d/var_ton_work_db_files_packages_size.yaml
rm /etc/datadog-agent/checks.d/var_ton_work_db_files_packages_size.py
sed -i 's@# process_config@process_config:\n  enabled: "true"@g' /etc/datadog-agent/datadog.yaml
sed -i 's@^process_config$@process_config:@g' /etc/datadog-agent/datadog.yaml
sed -i 's@enabled: "true":$@enabled: "true"@g' /etc/datadog-agent/datadog.yaml

mkdir /usr/src/validator-monitoring
wget -O /usr/src/validator-monitoring/ton_db_size.py $REPO_PREFIX/ton_db_size.py
wget -O /etc/systemd/system/ton-db-size.service $REPO_PREFIX/ton-db-size.service
systemctl enable ton-db-size
systemctl start ton-db-size
systemctl restart ton-db-size
wget -O /etc/datadog-agent/checks.d/ton_db_size.py $REPO_PREFIX/check.d_ton_db_size.py
wget -O /etc/datadog-agent/conf.d/ton_db_size.yaml $REPO_PREFIX/ton_db_size.yaml
systemctl restart datadog-agent
