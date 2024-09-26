#!/bin/sh

# Copyright (c) 2024.  Advanced Micro Devices, Inc.  All Rights Reserved.

# 0 - node healthy
# 1 - one of the GPU is unhealthy that's why node is unhealthy
# 2 - node down or offline

console_display() {
  host="$1"
  status="$2"
  host=$(echo "$host" | tr '[:upper:]' '[:lower:]')
  echo "# HELP node_health node health status"
  echo "# TYPE node_health gauge"
  echo "node_health{short_instance=\"$host\"} $status"
}

ClusterUnHealthyNodesList=""

check_error() {
  error_output="$1"
  if echo "$error_output" | grep -qiE "not found|failed"; then
  # echo "WARNING - sinfo command not found .... not a slurm cluster ecosystem"
    return 0
  fi
  # echo "INFO - slurm cluster ecosystem"
  return 1
}

get_k8s_node_health_status() {
  kubeConfig=$(chroot /host find / -type f -path '*/.kube/config' -print -quit)
  k8sNodeStatus=$(chroot /host kubectl get nodes --kubeconfig="$kubeConfig")
  ClusterUnHealthyNodesList=$(echo "$k8sNodeStatus" | grep -v 'STATUS' | grep 'NotReady' | awk '{print $1}')
}

get_node_health_status() {
  ClusterUnHealthyNodesList=$(chroot /host sinfo -t down,drain -N -O NODELIST -h 2>&1)
  if check_error "$ClusterUnHealthyNodesList"; then
    # echo "INFO - kubernetes cluster ecosystem"
    get_k8s_node_health_status
  else
    ClusterNodesListCount=$(chroot /host sinfo -N -O NODELIST -h | wc -l)
    ClusterUnHealthyNodesListCount=$(echo "$ClusterUnHealthyNodesList" | wc -w)
    if [ "$ClusterNodesListCount" -eq "$ClusterUnHealthyNodesListCount" ]; then
      # echo "INFO - kubernetes cluster ecosystem"
      get_k8s_node_health_status
    fi
  fi
  for node in $ClusterUnHealthyNodesList; do
    console_display "$node" 2
  done
}

##  M A I N

get_node_health_status