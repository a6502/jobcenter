#!/bin/bash

SUPERVISOR_CONF=/etc/supervisor/supervisord.conf
SUPERVISORD=/usr/bin/supervisord

function log {
    MSG=$1
    WHEN=$(date '+%y/%m/%d %T')
    echo "[$WHEN] $MSG"
}

function is_supervisord_started {
    supervisorctl status
    RC=$?
    if [ $RC == 0]; then
        RC=1
    else
        RC=0
    fi
    return $RC
}

function wait_for_supervisord_config {
    while true; do
        if [ -f "$SUPERVISOR_CONF" ]; then
           log "supervisord has been configured"
           return
        fi
        sleep 1;
    done
}

function start_supervisord {
    if [ is_supervisord_started == 1 ]; then
        log "supervisord already running, shutting down"
        supervisorctl shutdown || log "supervisord not running"
        killall supervisord || echo -n
        unlink /var/run/supervisor.sock >/dev/null 2>&1
    fi

    log "supervisor starting"
    $SUPERVISORD -n -c "$SUPERVISOR_CONF" &
    log "supervisor started"
    sleep 5
}

function wait_for_supervisord {
    log "waiting for supervisord to exit"
    PST=$(pstree -ap)
    log "running processes:"
    echo $PST
    while true; do
        if [ is_supervisord_started == 0 ]; then
           log "supervisord exited"
           return
        fi
        sleep 1;
    done
}

while true; do
    wait_for_supervisord_config
    start_supervisord
    wait_for_supervisord
done

