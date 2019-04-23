#!/bin/bash

# TODO: use http://supervisord.org/events.html
#
# this should give pgsql enough time to start up
sleep 30

cd /home/jobcenter/jobcenter

if [[ -f /root/initialize_jc ]]; then
    su - postgres -- /etc/init_jc_db.sh
    rm /root/initialize_jc
fi
if [[ -f /root/update_jc ]]; then
    su - postgres -- /etc/update_jc_db.sh
    rm /root/update_jc
fi

su - jobcenter -- /etc/run_jc.sh
