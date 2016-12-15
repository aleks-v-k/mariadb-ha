#!/bin/bash
# The script creates replication user and starts slaves in a cluster.
# It uses environment variables:
# * MYSQL_NODES - comma separated list of mysql cluster nodes;
# * MYSQL_ROOT, MYSQL_ROOT_PASSWORD - credentials of mysql root user;
# * MYSQL_REPLICATION_USER, MYSQL_REPLICATION_PASSWORD - credentials of mysql
#   replication user;
# Firstly it checks if the replication user already exists. If it is not, then
# the script assumes, the cluster is not initialized, so it creates replication
# user on first node from MYSQL_NODES list, and makes this node as a master
# for all other nodes.
# It checks server's readiness 60 times with 1 second sleep between retries,
# before performing actions.

MYSQL_NODES=${MYSQL_NODES:-10.0.0.1}

nodes_arr=(${MYSQL_NODES//,/ })
master=${nodes_arr[0]}

mysql_cmd="mysql -u $MYSQL_ROOT -p$MYSQL_ROOT_PASSWORD"

wait_for_server_ready() {
    server="$1"
	for i in {60..0}; do
		if echo 'SELECT 1' | $mysql_cmd -h$server &> /dev/null; then
			break
		fi
		echo "Waiting for mysql server $server ready..."
		sleep 1
	done
	if [ "$i" = 0 ]; then
		echo >&2 "Failed to wait mysql server $server."
		exit 1
	fi
}

# Check replication user existence
wait_for_server_ready $master
result=$($mysql_cmd -s -s -r -h$master -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = \"$MYSQL_REPLICATION_USER\")")
if [ $? -ne 0 ]; then
    echo "Failed to check replication user existance on $master"
    exit 1
fi

if [ "$result" != "1" ]; then
    echo "Creating replication user on $master"
    $mysql_cmd -h$master -e "GRANT replication slave ON *.* TO \"$MYSQL_REPLICATION_USER\"@'%' IDENTIFIED BY \"$MYSQL_REPLICATION_PASSWORD\""
    # set first server as master for all another nodes
    for node in ${nodes_arr[@]:1}; do
        echo "Setting a slave $node for master $master"
        wait_for_server_ready $node
        /opt/bin/start_slave.sh $master $node
    done
fi

