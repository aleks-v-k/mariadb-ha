#!/bin/bash

user=root:mysql
repluser=replication:replication

repl_manager_cmd="replication-manager --user=$user --rpluser=$repluser"
start_slave_cmd="/opt/bin/start_slave.sh"
echo "Calling $@"

ARGS=$(getopt -o '' --long 'event:,initiator:,nodelist:,masterlist:,' -- "$@")

eval set -- "$ARGS"

while true; do
    case "$1" in
        --event)
            shift;
            event=$1
            shift;
        ;;
        --initiator)
            shift;
            initiator=$1
            shift;
        ;;
        --nodelist)
            shift;
            nodelist=$1
            shift;
        ;;
        --masterlist)
            shift;
            masterlist=$1
            shift;
        ;;
        --)
            shift;
            break;
        ;;
    esac
done


initiator_host=${initiator%:*}

if [ "$event" == "server_up" ]; then
    # drop port part
    echo "Masterlist: $masterlist"
    master=${masterlist%:*}
    new_server=$initiator_host
    first_live_node=${nodelist%:*}
    # Select a master if there was only one node and now the second is up
    if [ -z "$master" ]; then
        master=$first_live_node
    fi
    echo "Calling $start_slave_cmd $master $new_server"
    $start_slave_cmd $master $new_server 2>&1
elif [ "$event" == "master_down" ]; then
    # if there is only one node alive, make it a master in 
    # node_arr=(${nodelist//,/ })
    rm -f /tmp/mrm.state
    echo "Running: $repl_manager_cmd failover --hosts=$initiator,$nodelist"
    $repl_manager_cmd failover --hosts="$initiator,$nodelist" 2>&1
    # if [ "1" -eq "${#node_arr[@]}" ]; then
    #     # maxadmin set server ${node_arr[0]} master
    # fi
elif [ "$event" == "master_up" ]; then
    echo "master_up: Master list: $masterlist"
    echo "master_up: initiator_host: $initiator_host"
    echo "master_up: nodelist: $nodelist"
    node_arr=(${nodelist//,/ })
    master_arr=(${masterlist//,/ })
    new_master=$initiator_host
    # If we have more that one master, then make new master as slave for another one
    if [ "1" -lt "${#master_arr[@]}" ]; then
        for master in "${master_arr[@]}"; do
            if [ "$master" != "$new_master" ]; then
                master=${master%:*}
                new_master=${new_master%:*}
                echo "Calling $start_slave_cmd $master $new_master"
                $start_slave_cmd $master $new_master 2>&1
                break
            fi
        done
    fi
fi
