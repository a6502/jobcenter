FROM postgres:9.6

RUN apt update
RUN apt upgrade -y

# install supervisor to be able to run services + tools
RUN apt install -o APT::Install-Suggests=0 -o APT::Install-Recommends=0 -y \
        supervisor git build-essential ca-certificates

# install os provided perl modules
RUN apt install -o APT::Install-Suggests=0 -o APT::Install-Recommends=0 -y  \
        libdbi-perl libdbd-pg-perl libpq5 postgresql-plperl-9.6 \
        liblocal-lib-perl \
        cpanminus \
        libconfig-tiny-perl \
        libjson-maybexs-perl libcpanel-json-xs-perl \
        libmojolicious-perl libpegex-perl libmojo-pg-perl \
        libjson-perl

# install more perl modules
RUN cpanm install MojoX::NetstringStream JSON::RPC2::TwoWay JobCenter::Client::Mojo Text::Table::Tiny JSON

# adding users
RUN useradd jobcenter
RUN useradd rpcswitch

# cloning from repositories
ENV GIT_REPO https://github.com/a6502
ENV GIT_REPO_JOBCENTER jobcenter
ENV GIT_REPO_RPCSWITCH rpc-switch
RUN git clone ${GIT_REPO}/${GIT_REPO_JOBCENTER} /home/jobcenter/jobcenter
RUN git clone ${GIT_REPO}/${GIT_REPO_RPCSWITCH} /home/rpcswitch/rpcswitch

# cleanup unneccessary stuff
RUN apt purge -y git build-essential ca-certificates cpanminus
RUN apt autoremove -y
RUN apt-get clean

# prepare jobcenter installation
RUN rm /home/jobcenter/jobcenter/etc/*.example
RUN chown -R jobcenter. /home/jobcenter/jobcenter

# prepare rpcswitch installation
RUN rm /home/rpcswitch/rpcswitch/etc/*.example
RUN chown -R rpcswitch. /home/rpcswitch/rpcswitch

# copy jobcenter initialization scripts
RUN touch /root/initialize_jc /root/update_jc
COPY scripts/jc_init.sh       /root/jc_init.sh
COPY scripts/init_jc_db.sh    /etc/init_jc_db.sh
COPY scripts/update_jc_db.sh  /etc/update_jc_db.sh
COPY scripts/run_jc.sh        /etc/run_jc.sh
RUN chmod u+x /root/jc_init.sh /etc/*_jc_db.sh /etc/run_jc.sh

# copy rpcswitch initialization scripts
COPY scripts/rpcswitch_init.sh /root/rpcswitch_init.sh
COPY scripts/run_rpcswitch.sh  /etc/run_rpcswitch.sh
RUN chmod u+x /root/rpcswitch_init.sh /etc/run_rpcswitch.sh
RUN chown -R rpcswitch. /home/rpcswitch/rpcswitch

# copy supervisor services
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor/jc.ini           /etc/supervisor/conf.d/jc.ini
COPY supervisor/rpcswitch.ini    /etc/supervisor/conf.d/rpcswitch.ini
COPY supervisor/pgsql.ini        /etc/supervisor/conf.d/pgsql.ini

# copy entrypoint
COPY scripts/entrypoint.sh /root/entrypoint.sh
RUN chmod u+x /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]

EXPOSE 6522 6520
