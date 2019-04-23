FROM debian:stretch-slim

RUN apt update
RUN apt upgrade -y

# install supervisor to be able to run services + tools
RUN apt install -y git build-essential

# install os provided perl modules
RUN apt install -y libdbi-perl libdbd-pg-perl libpq5 \
        liblocal-lib-perl \
        cpanminus \
        libconfig-tiny-perl \
        libjson-maybexs-perl libcpanel-json-xs-perl \
        libmojolicious-perl libpegex-perl libmojo-pg-perl
RUN apt-get clean

# install more perl modules
RUN cpanm install MojoX::NetstringStream JSON::RPC2::TwoWay JobCenter::Client::Mojo
