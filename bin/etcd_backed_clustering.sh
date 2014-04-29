#!/bin/bash

# If automatic clustering is enabled, do nothing but exit.
if env | grep -q "DOCKER_RIAK_AUTOMATIC_CLUSTERING=1"; then
  exit 0
fi

# If etcd backed cluster is not enabled, do nothing but exit.
if [ "$ETCD_BACKED_CLUSTER" != 1 ]
then
  exit 0
fi

CTL="etcdctl -C http://${ETCD_HOST}:${ETCD_PORT}"
KEY="/services/${SERVICE_ID}"

# Set own node ip.
HOST_IP=$(((/bin/ifconfig eth0 &>/dev/null) && /bin/ifconfig eth0 || /bin/ifconfig enp0s8 || /bin/ifconfig ens33) | awk '/inet /{print $2}')
echo "Set own ip (${HOST_IP})"
$CTL set "${KEY}/${HOST_IP}" ${HOST_IP} > /dev/null 2>&1

# Check etcd cluster path for enough entries.
while [ 1 ]; do
  NODE_COUNT=$($CTL ls "$KEY" | wc -l)

  if [ "$NODE_COUNT" = "$DOCKER_RIAK_CLUSTER_SIZE" ]
  then
    break
  fi

  echo "Waiting for riak nodes to join the etcd backed cluster."
  sleep 5
done

# When all nodes have been registered, check if own ip is the first (master election).
IS_MASTER=0
NODE_IDS=$($CTL ls "$KEY")
for NODE_ID in $NODE_IDS
do
  NODE_IP=$($CTL get $NODE_ID)

  if [ "$HOST_IP" = "$NODE_IP" ]
  then
    # If is master, continue to join the other nodes.
    echo "Node confirmed to be master."
    IS_MASTER=1
    continue
  fi

  if [ "$IS_MASTER" = 0 ]
  then
    # If is not master, do nothing but exit.
    echo "Node confirmed to be slave."
    exit 0
  fi

  # When master, join other ips to the cluster, but the own one.
  echo "Joining $NODE_IP to the etcd backed cluster."
  riak-admin cluster join "riak@${NODE_IP}" > /dev/null 2>&1

  sleep 1
done

riak-admin cluster plan > /dev/null 2>&1 && riak-admin cluster commit > /dev/null 2>&1
