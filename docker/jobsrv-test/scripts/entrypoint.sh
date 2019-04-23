#!/bin/bash

nohup /root/entrypoint.sh &

sleep 30

cd /home/jobcenter/jobcenter/test/
/home/jobcenter/jobcenter/test/dotest.pl
