# vim:set ft=dockerfile:
FROM centos:centos7


RUN rpm --import https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
RUN yum -y install wget && wget https://downloads.mariadb.com/MaxScale/2.0.2/rhel/7/x86_64/maxscale-2.0.2-1.rhel.7.x86_64.rpm \
    && yum -y install maxscale-2.0.2-1.rhel.7.x86_64.rpm
COPY mariadb.repo /etc/yum.repos.d/mariadb.repo
RUN yum -y install mariadb \
    && wget https://github.com/tanji/replication-manager/releases/download/0.7.0-rc3/replication-manager-0.7.0-6e390e0.x86_64.rpm \
    && yum -y install replication-manager-0.7.0-6e390e0.x86_64.rpm

COPY process_maxscale_events.sh /opt/bin/
COPY start_slave.sh /opt/bin/
COPY maxscale.cnf /etc/
COPY mrm-config.toml.template /etc/replication-manager/config.toml.template
COPY init_mysql_cluster.sh /opt/bin/


ENV MYSQL_NODES 10.0.0.1,10.0.0.2
ENV MYSQL_ROOT=root MYSQL_ROOT_PASSWORD=mysql MYSQL_REPLICATION_USER=replication \
    MYSQL_REPLICATION_PASSWORD=replication

COPY docker-entrypoint.sh /usr/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh / # backwards compat
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306
CMD ["maxscale --config=/etc/maxscale.cnf --nodaemon"]
