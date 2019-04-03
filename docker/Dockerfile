FROM postgres:9.6

RUN apt update
RUN apt upgrade -y

# install supervisor to be able to run services + tools
RUN apt install -y supervisor git build-essential

# install os provided perl modules
RUN apt install -y libdbi-perl libdbd-pg-perl libpq5 postgresql-plperl-9.6 \
        liblocal-lib-perl \
        cpanminus \
        libconfig-tiny-perl \
        libjson-maybexs-perl libcpanel-json-xs-perl \
        libmojolicious-perl libpegex-perl libmojo-pg-perl
RUN apt-get clean

# install more perl modules
RUN cpanm install MojoX::NetstringStream JSON::RPC2::TwoWay JobCenter::Client::Mojo

# prepare jobcenter installation
RUN useradd jobcenter
WORKDIR /home/jobcenter
RUN git clone https://github.com/M0WA/jobcenter jobcenter
WORKDIR /home/jobcenter/jobcenter
RUN cp etc/jobcenter.conf.example  etc/jobcenter.conf
RUN chown -R jobcenter. /home/jobcenter/jobcenter

# prepare rpcswitch installation
RUN useradd rpcswitch
WORKDIR /home/rpcswitch
RUN git clone https://github.com/M0WA/rpc-switch rpcswitch
WORKDIR /home/rpcswitch/rpcswitch
RUN rm etc/config.pl.example
COPY config.pl etc/config.pl
RUN mv etc/methods.pl.example etc/methods.pl
RUN touch etc/switch.passwd
COPY rpcswitch_init.sh /root/rpcswitch_init.sh
COPY run_rpcswitch.sh /etc/run_rpcswitch.sh
RUN chmod u+x /root/rpcswitch_init.sh /etc/run_rpcswitch.sh
RUN chown -R rpcswitch. /home/rpcswitch/rpcswitch

WORKDIR /

# configure plperl
COPY plperl.conf /etc/plperl.conf
COPY plperlinit.pl /etc/plperlinit.pl
RUN chmod a+x /etc/plperlinit.pl
COPY postgresql.conf /etc/postgresql/postgresql.conf

# copy jobcenter initialization scripts
RUN touch /root/initialize_jc /root/update_jc
COPY jc_init.sh      /root/jc_init.sh
COPY init_jc_db.sh   /etc/init_jc_db.sh
COPY update_jc_db.sh /etc/update_jc_db.sh
COPY run_jc.sh /etc/run_jc.sh
RUN chmod u+x /root/jc_init.sh /etc/*_jc_db.sh /etc/run_jc.sh

# copy supervisor services
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY jc.ini /etc/supervisor/conf.d/jc.ini
COPY rpcswitch.ini /etc/supervisor/conf.d/rpcswitch.ini
COPY pgsql.ini /etc/supervisor/conf.d/pgsql.ini

# copy entrypoint
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod u+x /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
