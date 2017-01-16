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

mysql_cmd="mysql -u $MYSQL_ROOT -p$MYSQL_ROOT_PASSWORD --connect_timeout=5"

up_nodes=()
not_ready_nodes=("${nodes_arr[@]}")

is_server_ready() {
    server="$1"
    if echo 'SELECT 1' | $mysql_cmd "-h$server" &> /dev/null; then
        return 0
    fi
    return 1
}


# Find all nodes in ready state and put them to 'up_nodes' array
# for i in {60..0}; do
for i in {10..0}; do
  updated_nodes_arr=()
  echo "Try to check nodes (left $i times)"
  for node in "${not_ready_nodes[@]}"; do
      echo "Checking node $node"
      if is_server_ready $node; then
          up_nodes+=($node)
          echo "Node $node is ready"
      else
          updated_nodes_arr+=($node)
          echo "Node $node is still not ready"
      fi
  done
  if [ ${#updated_nodes_arr[@]} -eq 0 ]; then
    not_ready_nodes=(${updated_nodes_arr[@]})
    break
  fi
  not_ready_nodes=(${updated_nodes_arr[@]})
  sleep 1
done

echo "Ready nodes: ${up_nodes[@]}"
echo "Not ready nodes: ${not_ready_nodes[@]}"

if [ ${#up_nodes[@]} -eq 0 ]; then
    echo "All nodes are not ready. Exit"
    exit 1
fi

master=${nodes_arr[0]}

is_server_readonly() {
    server="$1"
    res=$(echo 'SELECT @@global.read_only'|$mysql_cmd "-h$server" -N -s)
    if [ $? -ne 0 ]; then
        return 1
    fi
    if [ "$res" == "0" ]; then
        return 1
    fi
    return 0
}


is_repl_user_exists() {
    server="$1"
    result=$($mysql_cmd -s -r -N "-h$server" -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = \"$MYSQL_REPLICATION_USER\")")
    if [ $? -ne 0 ]; then
        echo "Failed to check replication user existance on $master"
        return 1
    fi

    if [ "$result" != "1" ]; then
        return 1
    fi
    return 0
}

master_candidates=()
find_master_candidates() {
    for node in "${up_nodes[@]}"; do
        if ! is_server_readonly "$node"; then
            master_candidates+=("$node")
            break
        fi
    done
}

find_master_candidates
echo "Found master candidates: ${master_candidates[@]}"


reset_readonly_flag() {
    server="$1"
    echo "Resetting readonly flag from $master"
    $mysql_cmd -h$master -e "SET GLOBAL read_only=OFF;"
}


if [ ${#master_candidates[@]} -eq 0 ]; then
    # All the servers are in readonly mode. Slect the first one as a master
    # and make it writable.
    master=${up_nodes[0]}
    echo "No write ready nodes was detected. Use the first one ($master)."
    reset_readonly_flag "$master"
    master_candidates=($master)
else
    master=${master_candidates[0]}
fi

is_cluster_initialized=no

find_existing_master() {
    for node in "${master_candidates[@]}"; do
        if is_repl_user_exists "$node"; then
            master="$node"
            is_cluster_initialized=yes
            break
        fi
    done
}

find_existing_master

up_nodes=(${up_nodes[@]/$master})
echo "Remaining up nodes: ${up_nodes[@]}"

echo "Selected master: $master"
echo "Detected cluster state: initialized = $is_cluster_initialized"

# Rest selected master if it was a slave earlier
echo "Resetting slave on master..."
$mysql_cmd -h$master -e "STOP SLAVE; RESET SLAVE ALL;"


if [ "$is_cluster_initialized" != "yes" ]; then
    echo "Creating replication user on $master"
    $mysql_cmd -h$master -e "GRANT replication slave ON *.* TO \"$MYSQL_REPLICATION_USER\"@'%' IDENTIFIED BY \"$MYSQL_REPLICATION_PASSWORD\" ; FLUSH PRIVILEGES;"
fi

# set master for all another nodes
for node in "${up_nodes[@]}"; do
    echo "Setting a slave $node for master $master"
    /opt/bin/start_slave.sh $master $node
done

