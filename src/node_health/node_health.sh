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

#function get_node_status() {
#  local host=$1
#  partition=$(sinfo -t idle,alloc --format="%R %.12n" -h | grep $host | awk '{print $1}')
#  distro=$(echo ${partition##*_} | tr '[A-Z]' '[a-z]')
#  if $(echo $distro | grep -q sles); then
#    ver=$(ssh $host "cat /etc/os-release | grep -w 'VERSION'")
#    exit_code=$?
#    if [ $exit_code -ne 0 ]; then
#        console_display $host 2
#        return
#    fi
#    ver=$(echo $ver| tr '[A-Z]' '[a-z]'| tr -d '"')
#    distro=$distro${ver#*-}
#  fi

#  if $(echo $distro | grep -q ubuntu22); then
#    distro='ubuntu'
#  fi

#  rocm_cmd=$(ssh $node "find /shared/apps/$distro/opt/rocm-6.* -name rocm-smi | tail -n 1")
#  exit_code=$?
#  if [ $exit_code -ne 0 ]; then
#     console_display $host 2
#     return
#  fi
#  if [[ -n $( ssh $host "$rocm_cmd --showuse | grep 'GPU use (%):' | grep -wv '0'") ]]; then
#     # echo "There is non-zero GPU usage"
#     if [[ -n $(ssh $host "$rocm_cmd --showpids | grep 'No KFD PIDs currently running' &>/dev/null") ]]; then
#     # echo "Confirming - There is no KFD PIDs running"
#        console_display $host 1
#     else
#        console_display $host 0
#     fi
#  else
#     # echo "All GPUs are idle or the command failed"
#     console_display $host 0
#  fi
#}

ClusterUnHealthyNodesList=""

check_error() {
  error_output="$1"
  if echo "$error_output" | grep -qiE "not found|failed"; then
#    echo "WARNING - sinfo command not found .... not a slurm cluster ecosystem"
    return 0
  fi
#  echo "INFO - slurm cluster ecosystem"
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
#    echo "INFO - kubernetes cluster ecosystem"
    get_k8s_node_health_status
  else
    ClusterNodesListCount=$(chroot /host sinfo -N -O NODELIST -h | wc -l)
    ClusterUnHealthyNodesListCount=$(echo "$ClusterUnHealthyNodesList" | wc -w)
    if [ "$ClusterNodesListCount" -eq "$ClusterUnHealthyNodesListCount" ]; then
#      echo "INFO - kubernetes cluster ecosystem"
      get_k8s_node_health_status
    fi
  fi
  for node in $ClusterUnHealthyNodesList; do
    console_display "$node" 2
  done
}

#get_healthyNodeList() {
#  ClusterHealthyNodesList=$(sinfo -t idle,alloc -N -O NODELIST -h)
#  for node in $ClusterHealthyNodesList; do
#    get_node_status $node
#  done
#}

##  M A I N

get_node_health_status