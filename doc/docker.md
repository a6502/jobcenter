# introduction into using docker + jobcenter

caution: use this image for development/testing purposes only

## passwords

  !!! all passwords are set to default/empty !!!

  Check the following files for passwords:
  
  * docker/jobsrv/jobcenter/api.passwd
  * docker/jobsrv/rpcswitch/switch.passwd

  create passwords using the following command:

    mkpasspwd --method=sha-256

## configuration

  Check the following files for configuration:
  
  * docker/jobsrv/jobcenter/jcswitch.conf
  * docker/jobsrv/jobcenter/jobcenter.conf
  * docker/jobsrv/rpcswitch/config.pl
  * docker/jobsrv/rpcswitch/methods.pl
  * docker/jobsrv/pgsql/*

## run jobcenter server + client

    cd docker
    docker-compose up -d

## run jobcenter tests

    cd docker
    docker-compose up jobsrv-test

## shutdown jobcenter server + client

    cd docker
    docker-compose down

## build-only jobcenter server docker image

    cd docker/jobsrv
    docker build -t jobcenter/jobsrv:latest docker

## build-only jobcenter client docker image

    cd docker/jobcli
    docker build -t jobcenter/jobcli:latest docker
