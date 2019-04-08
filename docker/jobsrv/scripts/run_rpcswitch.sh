#!/bin/bash

# TODO: use http://supervisord.org/events.html
#
# this should give pgsql enough time to start up
sleep 30

/home/rpcswitch/rpcswitch/bin/rpcswitch --nodaemon --cfgdir=/home/rpcswitch/rpcswitch/etc/
