#!/bin/bash

#wget -O /etc/datadog-agent/conf.d/lite_clien_last_block_age_seconds.yaml https://raw...
cp lite_clien_last_block_age_seconds.yaml /etc/datadog-agent/conf.d/lite_clien_last_block_age_seconds.yaml
#wget -O /etc/datadog-agent/checks.d/lite_clien_last_block_age_seconds.py https://raw...
cp lite_clien_last_block_age_seconds.py /etc/datadog-agent/checks.d/lite_clien_last_block_age_seconds.py
cp var_ton_work_db_files_packages_size.yaml /etc/datadog-agent/conf.d/var_ton_work_db_files_packages_size.yaml
cp var_ton_work_db_files_packages_size.py /etc/datadog-agent/checks.d/var_ton_work_db_files_packages_size.py
chmod o+x /var/ton-work/db/files/
chmod -R o+r /var/ton-work/db/files/packages/
chmod o+x /var/ton-work/db/files/packages/temp.archive.*.index
#wget -O /etc/datadog-agent/conf.d/directory.d/conf.yaml https://raw...
cp directory_conf.yaml /etc/datadog-agent/conf.d/directory.d/conf.yaml
systemctl restart datadog-agent
