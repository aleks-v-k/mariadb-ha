#!/bin/bash
set -eo pipefail
shopt -s nullglob


/opt/bin/init_mysql_cluster.sh

mrm_config=/etc/replication-manager/config.toml
mrm_config_template=/etc/replication-manager/config.toml.template
cp "$mrm_config_template" "$mrm_config"
sed -i "s/MYSQL_NODES/$MYSQL_NODES/" "$mrm_config"
sed -i "s/MYSQL_USER/$MYSQL_ROOT/" "$mrm_config"
sed -i "s/MYSQL_PASSWORD/$MYSQL_ROOT_PASSWORD/" "$mrm_config"
sed -i "s/RPL_USER/$MYSQL_REPLICATION_USER/" "$mrm_config"
sed -i "s/RPL_PASSWORD/$MYSQL_REPLICATION_USER/" "$mrm_config"


# Generate maxscale config
maxscale_conf=/etc/maxscale.cnf
# heading for config. Should contain entry for each server in cluster
tmp_file=$(mktemp /tmp/maxscale.heading.XXXX)

# TODO: adjust with available cores
cat <<EOF >> "$tmp_file"

[maxscale]
threads=1
log_info=1
log_debug=1
syslog=0
maxlog=1
auth_connect_timeout=2

EOF

nodes_arr=(${MYSQL_NODES//,/ })
index=1
servers=""
for node in ${nodes_arr[@]}; do
    server="server$index"
cat <<EOF >> "$tmp_file"
[$server]
type=server
address=$node
port=3306
protocol=MySQLBackend

EOF
    if [ -z "$servers" ]; then
        servers="$server"
    else
        servers="$servers,$server"
    fi
    index=$(($index + 1))
done

cat "$maxscale_conf" >> "$tmp_file"

cp -f "$tmp_file" "$maxscale_conf"
rm -f "$tmp_file"

sed -i "s/MYSQL_SERVERS/$servers/g" "$maxscale_conf"
sed -i "s/MYSQL_USER/$MYSQL_ROOT/g" "$maxscale_conf"
sed -i "s/MYSQL_PASSWORD/$MYSQL_ROOT_PASSWORD/g" "$maxscale_conf"

exec "$@"
