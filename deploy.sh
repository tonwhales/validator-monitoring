#!/bin/bash

REPO_PREFIX=https://raw.githubusercontent.com/tonwhales/validator-monitoring/main

# we need 1c78056a4249672a8e9eb0548c79e02d3ce19d5e
pushd /usr/src/mytonctrl; git pull origin master; popd
python3 -c 'import sys; sys.path.append("/usr/src/mytonctrl"); import mytoninstaller; mytoninstaller.Init(); mytoninstaller.CreateLocalConfig(mytoninstaller.GetInitBlock(), localConfigPath="/usr/src/validator-monitoring/local.config.json")'

wget -O /etc/datadog-agent/conf.d/lite_clien_last_block_age_seconds.yaml $REPO_PREFIX/lite_clien_last_block_age_seconds.yaml
#cp lite_clien_last_block_age_seconds.yaml /etc/datadog-agent/conf.d/lite_clien_last_block_age_seconds.yaml
wget -O /etc/datadog-agent/checks.d/lite_clien_last_block_age_seconds.py $REPO_PREFIX/lite_clien_last_block_age_seconds.py
#cp lite_clien_last_block_age_seconds.py /etc/datadog-agent/checks.d/lite_clien_last_block_age_seconds.py
#wget -O /etc/datadog-agent/conf.d/var_ton_work_db_files_packages_size.yaml $REPO_PREFIX/var_ton_work_db_files_packages_size.yaml
#cp var_ton_work_db_files_packages_size.yaml /etc/datadog-agent/conf.d/var_ton_work_db_files_packages_size.yaml
#wget -O /etc/datadog-agent/checks.d/var_ton_work_db_files_packages_size.py $REPO_PREFIX/var_ton_work_db_files_packages_size.py
#cp var_ton_work_db_files_packages_size.py /etc/datadog-agent/checks.d/var_ton_work_db_files_packages_size.py
#chmod o+x /var/ton-work/db/files/
#chmod -R o+r /var/ton-work/db/files/packages/
#chmod o+x /var/ton-work/db/files/packages/temp.archive.*.index
#wget -O /etc/datadog-agent/conf.d/directory.d/conf.yaml https://raw.githubusercontent.com/tonwhales/validator-monitoring/main/directory_conf.yaml
#cp directory_conf.yaml /etc/datadog-agent/conf.d/directory.d/conf.yaml
sed -i 's@# process_config@process_config\n  enabled: "true"@g' /etc/datadog-agent/datadog.yaml
mkdir /usr/src/validator-monitoring
wget -O /usr/src/validator-monitoring/ton_db_size.py $REPO_PREFIX/ton_db_size.py
wget -O /etc/systemd/system/ton-db-size.service $REPO_PREFIX/ton-db-size.service
systemctl enable ton-db-size
systemctl start ton-db-size
wget -O /etc/datadog-agent/checks.d/ton_db_size.py $REPO_PREFIX/check.d_ton_db_size.py
wget -O /etc/datadog-agent/conf.d/ton_db_size.yaml $REPO_PREFIX/ton_db_size.yaml
systemctl restart datadog-agent
