# short introduction into using docker + jobcenter

caution: use this image for development/testing purposes only

!!! all passwords are set to default/empty !!!

## build docker image:

    git clone https://github.com/a6502/jobcenter jobcenter
    cd jobcenter
    docker build -t jobcenter:latest docker

## run docker image:

    docker run -d jobcenter:latest
