#!/bin/bash

# Copyright (c) 2024.  Advanced Micro Devices, Inc.  All Rights Reserved.

# 0 - node healthy
# 1 - one of the GPU is unhealthy that's why node is unhealthy
# 2 - node down or offline

function console_display() {
  local host=$1
  local status=$2
  host=$(echo "$host" | tr '[:upper:]' '[:lower:]')
  echo "# HELP node_health node health status"
  echo "# TYPE node_health gauge"
  echo "node_health{short_instance=\"$host\"} $status"
}

function get_node_health_status() {
  hostname=$(hostname)
  if [[ -n $( rocm-smi --showuse | grep 'GPU use (%):' | grep -wv '0') ]]; then
     # echo "There is non-zero GPU usage"
     if [[ -n $(rocm-smi --showpids | grep 'No KFD PIDs currently running' &>/dev/null) ]]; then
     # echo "Confirming - There is no KFD PIDs running"
        console_display $hostname 1
     else
        console_display $hostname 0
     fi
  else
     # echo "All GPUs are idle"
     console_display $hostname 0
  fi
}

##  M A I N

get_node_health_status
# END