#!/bin/bash
#================================================================
#   Script by AMD
#================================================================
#%
#%  DESCRIPTION
#%  This script for install grafana server on Ubuntu 22.04.3 LTS
#%
#-  IMPLEMENTATION
#-  Version     :   1.0
#-  Author      :   AMD
#-  Copyright   :   Copyright (c) https://www.amd.com
#-  License     :   GNU General Public License
#   HISTORY
#   04/24/2024  :   Script creation
#================================================================
#   DEBUG OPTION
#   set -n      #   Uncomment to check syntax, without execution.
#   set -x     #   Uncomment to debug this shell script
#
#================================================================
#== Check server operating system =##

set -e

install_grafana(){
    os=$(lsb_release -d | awk -F ":" '{print$2}')
    echo "Your operating system -$os"
    #
    #== Collect server ip address ==#
    IP_ADDRESS=$(ip route get 8.8.8.8 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
    #
    sudo apt-get install -y apt-transport-https software-properties-common wget
    #
    #==     add grafana repo        ==#
    sudo mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
    #
    #==     update  ==#
    sudo apt-get update
    #
    #==     install garafana package        ==#
    sudo apt-get -y install grafana
    #
    #==     reload  ==#
    sudo systemctl daemon-reload
    #
    #==     start service   ==#
    sudo systemctl start grafana-server
    #
    #== status service ==#
    #sudo systemctl status grafana-server
    #
    #==     enable service  ==#
    sudo systemctl enable grafana-server.service
    #
    clear
    #
    echo "Grafana installation done!"
    #
    #==     show access url ==#
    echo    "########============================================########"
    echo    "######## Access URL    : http://$IP_ADDRESS:3000/  ########"
    echo    "######## User Name     : admin                      ########"
    echo    "######## Password      : admin                      ########"
    echo    "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo    "######## Note: Must be change password after login  ########"
    echo    "########============================================########"
    # To enable TLS for Grafana if required, following are the steps:
    #== generate a self-signed certificate ==#
    #sudo openssl genrsa -out /etc/grafana/grafana.key 2048
    #sudo openssl req -new -key /etc/grafana/grafana.key -out /etc/grafana/grafana.csr -subj "/C=<CountryName>/ST=<StateOrProvinceName>/L=<Locality>/O=<Organization>/OU=<OrganizationalUnit>/CN=<CommonName>"
    #sudo openssl x509 -req -days 365 -in /etc/grafana/grafana.csr -signkey /etc/grafana/grafana.key -out /etc/grafana/grafana.crt
    #sudo chown grafana:grafana /etc/grafana/grafana.crt
    #sudo chown grafana:grafana /etc/grafana/grafana.key
    #sudo chmod 400 /etc/grafana/grafana.key /etc/grafana/grafana.crt
    #
    #== update grafana.ini ==#
    #sudo service grafana-server restart

    # Copy the CA certificate onto the host directory /usr/local/share/ca-certificates/ from where you want to access grafana.
    # Run sudo update-ca-certificates

    # Install nginx reverse proxy server
    sudo apt update && sudo apt upgrade -y
    sudo apt install nginx -y
    sudo cp -R nginx.conf /etc/nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx
    sudo nginx -s reload
    #sudo systemctl status nginx
    echo "Nginx reverse proxy server installation done!"
}

uninstall_grafana(){
    # Uninstall Grafana - 
    sudo systemctl stop grafana-server.service #– Stops the Grafana service.
    sudo apt-get purge grafana #– Removes Grafana and its configuration files.
    sudo apt-get autoremove #– Removes unused packages.
    sudo add-apt-repository --remove ppa:grafana/grafana #– Removes the Grafana repository.

    sudo userdel -r grafana #– Deletes the Grafana user.
    sudo groupdel grafana #– Deletes the Grafana group.

    sudo rm -rf /var/lib/grafana #– Deletes Grafana’s library directory.
    sudo rm -rf /var/log/grafana #– Deletes Grafana’s log directory.
    sudo rm -rf /etc/grafana #– Deletes Grafana’s configuration directory.

    # Uninstall Nginx - 
    sudo systemctl stop nginx
    sudo apt-get purge nginx
    sudo apt-get autoremove
    sudo rm -rf /etc/nginx /var/log/nginx
    # sudo systemctl status nginx
}

usage(){
  echo ""
  echo "-- Deploy Gafana observability platform for open source analytics and interactive visualization application with nginx proxy server --"
  echo "Usage:$0 [flags]"
  echo "[FLAGS]"
  echo "  --install: Install grafana observability platform for open source analytics and interactive visualization application"
  echo "  --uninstall: Uninstall grafana observability platform"
  echo "  -h, --help: For help"
  echo ""
}

parse_args(){
  local execution_mode=
  while test $# -gt 0
  do
    case "$1" in
    --install)
      shift
      execution_mode="install"
      install_grafana
      ;;
    --uninstall)
      execution_mode="uninstall"
      uninstall_grafana
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
    esac
    shift
  done

  if [ -z "$execution_mode" ]; then
    echo "Error: Execution mode must be provided with --install or --uninstall."
    usage
    exit 1
  fi
}

parse_args "$@"

set +e
