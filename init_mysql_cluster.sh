#!/bin/bash

MYSQL_NODES=${MYSQL_NODES:-10.0.0.1}

nodes_arr=(${MYSQL_NODES//,/ })
master=${nodes_arr[0]}

# Check replication user existence
mysql_cmd="mysql -u $MYSQL_ROOT -p$MYSQL_ROOT_PASSWORD"
result=$($mysql_cmd -s -s -r -h$master -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = \"$MYSQL_REPLICATION_USER\")")
if [ $? -ne 0 ]; then
    echo "Failed to check replication user existance on $master"
    exit 1
fi

if [ "$result" != "1" ]; then
    echo "Creating replication user on $master"
    $mysql_cmd -h$master -e "GRANT replication slave ON *.* TO \"$MYSQL_REPLICATION_USER\"@'%' IDENTIFIED BY \"MYSQL_REPLICATION_PASSWORD\""
    # set first server as master for all another nodes
    for node in ${nodes_arr[@]:1}; do
        echo "Setting a slave $node for master $master"
        /opt/bin/start_slave.sh $master $node
    done
fi

