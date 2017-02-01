# mariadb-ha

Mysql master-slave cluster to run in kuberdock.

This document describes solution of mysql HA cluster for kuberdock project.

## Common description.

The purpose of this solution is to provide clustered mysql service in kuberdock
for different applications. The cluster works on top of one or more pods with mariadb containers (DB pods)
and one pod with maxscale (https://mariadb.com/products/mariadb-maxscale) DB proxy and
automatic failover implemented (HA pod).

One of DB pods will be selected as a master and others will be slaves for this master.
Selection of the master and settings for slave is implemented in HA pod.

## How to setup

* Create two or more pods with aku1/mariadb-repl containers, set SERVER_ID env var
for each container to unique integer value. Optionally set SEMI_SYNC_REPLICATION_ENABLED
to "ON" to enable semi-sync replication (recommended).
* Start DB pods.
* Create one pod with aku1/mariadb-ha container.
    * Set MYSQL_NODES to comma-separated list of DB pods IP addresses (it may be found
in kuberdock web-UI on a pod's page), like '123.123.123.123,123.123.123.124'
    * Run HA pod, and wait until it will be in running state.
* Create a pod with an application which requires mysql DB, place to it's env vars
IP address of HA pod as an address of mysql server.

Now the created application will use clustered mysql backend. It will communicate
with mysql cluster via HA pod (maxscale will proxy queries according to current
state of the mysql cluster).

##  How it works

DB pods initially started with only one user 'root' and empty binlog.

During startup of HA pod it will wait some time for readiness of at least
one DB pod. Then it will look for already existing master in alive DB pods.
DB pod will be a master candidate if it read_only flag is turned off.
If a master is detected, then it will be checked for existence of user 'replication':
if the user exists, then the initialization script assumes that 'master' was already initialized,
otherwise there will be created 'replication' user in it.
All another alive DB nodes will be initialized to slaves for selected master.

All nodes (alive and dead) will be added to maxscale configuration to enable monitoring
for these nodes.

After that maxscale will be started (it will be the only process in HA container).

Maxscale process is configured to proxy read-write requests to mysql cluster. Also
it monitors mysql nodes states. If it catch one of events master_down|new_master|server_up,
then it runs https://github.com/aleks-v-k/mariadb-ha/blob/master/process_maxscale_events.sh
script. This script calls failover proc (replication-manager failover) in case of master down event.

When some of Db cluster nodes will be unavailable for maxscale monitor it will be automatically
reconfigured to not send queries to a dead node.

When new a node becomes accessible it will be initialized to a slave for existing
master.

When a master will become unavailable for maxscale, there will be performed failover
procedure, and one of existing slaves will be switched to master (all other slaves
will be switched to this new master).

There is used miltimaster monitor for maxscale, because mysqlmon does not detects
new master when it is the only one node in the cluster.

Mariadb server in container always starts in read-only mode and with stopped slave thread.
Readonly-mode is necessary to maxscale multimaster monitor - if this flag is not
set, then it treats new server as a new master.
Stopped slave thread option is added to prevent automatically attaching of broken (or improperly
configured) slave to the cluster. For example we can have initial topology like this:

server1 (master) <- slave (server2), slave (server3)

If server3 will be stopped (for any reason), and after that server1 will be stopped, then
new master will be on server2. Then we start server1, it will be a slave for server2.
Then we will start server3. If we do not stop slave thread on start, then it will
attach to server1 as a slave and it will be broken topology. So we always start db server
with stopped slave, reconfigure it according to current topology, and start slave.

Initialization of slave hosts is always made by loading sql dump of master host.
Master host dump treated as valid for 6 hours. So in this period no new master dump
will be created to initialize new (or recovered) slave.


## Some hints

You can run 'maxadmin' cli utility in running HA container to view or change cluster
state. For example to see current DB cluster topology run `maxadmin list servers`.

Also you can connect to any mysql pod by running
`mysql -uroot -pmysql -h<mysql service IP>` from inside running HA container.

The last taken dump of current master can be found in `/dumps/msater/<master IP>.sql` in HA
container.

## Known issues

Maxscale multimaster monitor hangs in some cases, so there has been added restart of this
monitor (maxadmin restart monitor "Replication monitor") after handling of catched
monitor events.

Maxscale crashes sometimes with segmentation fault (tested with 2.0.3 & 2.0.2 versions).
The reason is unknown now, and there was no similar bugs found in the net. I wish to open an issue
on maxscale github for this case.

After loading of a dump to initialize slave I manually clear mysql.gtid_slave_pos
table. Without it there may be possible conflicts with updating of this table on the slave,
so replication will stop. The case also must be deeper investigated, and possibly
an issue should be opened for mariadb.

## Links

Mariadb-repl docker image: https://hub.docker.com/r/aku1/mariadb-repl/

Mariadb-repl docker image sources: https://github.com/aleks-v-k/mariadb/tree/kd-replicated

commits: https://github.com/aleks-v-k/mariadb/commits/kd-replicated


Mariadb-ha docker image: https://hub.docker.com/r/aku1/mariadb-ha/

Mariadb-ha docker image sources: https://github.com/aleks-v-k/mariadb-ha
