#!/bin/bash
MASTER_HOST="$1"
TARGET_HOST="$2"
MYSQL_ROOT=${MYSQL_ROOT:-root}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-mysql}
MYSQL_REPLICATION_USER=${MYSQL_REPLICATION_USER:-replication}
MYSQL_REPLICATION_PASSWORD=${MYSQL_REPLICATION_PASSWORD:-replication}

if [ -z "TARGET_HOST" ]; then
    TARGET_HOST="localhost"
fi

if [ -z "$MASTER_HOST" ]; then
    echo "Specify master host"
    exit 1
fi
echo "Setting master to $MASTER_HOST on $TARGET_HOST"

mysql -u $MYSQL_ROOT -h $TARGET_HOST -p$MYSQL_ROOT_PASSWORD <<-EOSQL
STOP SLAVE;

CHANGE MASTER TO master_host='$MASTER_HOST',
	master_user='${MYSQL_REPLICATION_USER}',
	master_password='${MYSQL_REPLICATION_PASSWORD}',
	master_port=3306,
	master_use_gtid=current_pos;

START SLAVE;
SET GLOBAL read_only=ON;
EOSQL

