#!/bin/bash
# The script will return master dump from which can be initialized
# a new slave.
# If an existing dump is too old, then a new one will be created.
# Prints actual dump file path to stdout.

master_host="$1"
user="$2"
password="$3"


MASTER_DUMP_DIR='/dumps/master'

mkdir -p "$MASTER_DUMP_DIR"

# Creates dump file for current master.
# Dump file will be actual during 6 hours
DUMP_FILE_LIFETIME=$((60 * 6))

dump_filename="${MASTER_DUMP_DIR}/${master_host}.sql"

if [ ! -f "$dump_filename" ] || [ $(stat --format=%Y $dump_filename) -le $((`date +%s` - $DUMP_FILE_LIFETIME)) ]; then
  mysqldump --all-databases --add-drop-database --opt --single-transaction --gtid --master-data=1 -h "$master_host" -u "$user" -p"$password" > "$dump_filename" || exit 1
fi

# remove dumps from previous masters
cd $MASTER_DUMP_DIR && ls | grep -v "${master_host}.sql" | xargs rm

echo "$dump_filename"
