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

master_dump_file=$(/opt/bin/get_master_dump.sh "$MASTER_HOST" "$MYSQL_ROOT" "$MYSQL_ROOT_PASSWORD")
if [ "$?" != 0 ]; then
    echo "Failed to get master dump"
    exit 1
fi

echo "Use master dump file $master_dump_file"

echo "Stopping SLAVE on $TARGET_HOST"
mysql -u $MYSQL_ROOT -h $TARGET_HOST -p$MYSQL_ROOT_PASSWORD <<-EOSQL
STOP SLAVE;
RESET SLAVE ALL;
EOSQL

echo "Loading dump $master_dump_file to $TARGET_HOST"
mysql -u $MYSQL_ROOT -h $TARGET_HOST -p$MYSQL_ROOT_PASSWORD < "$master_dump_file"


# The workaround is to rejoin servers via dump restoration:
# It will prevent to get git_slave_pos entries conflicts with new after
# restoring from dump:
# SET @@SESSION.SQL_LOG_BIN=0;
# DELETE FROM mysql.gtid_slave_pos;

echo "Starting slave on $TARGET_HOST"
mysql -u $MYSQL_ROOT -h $TARGET_HOST -p$MYSQL_ROOT_PASSWORD <<-EOSQL
SET @@SESSION.SQL_LOG_BIN=0;

DELETE FROM mysql.gtid_slave_pos;
RESET MASTER;
SET GLOBAL read_only=ON;
CHANGE MASTER TO master_host='$MASTER_HOST',
	master_user='${MYSQL_REPLICATION_USER}',
	master_password='${MYSQL_REPLICATION_PASSWORD}',
	master_port=3306,
	master_use_gtid=slave_pos;

FLUSH PRIVILEGES;
START SLAVE;
EOSQL

echo "Slave started"
