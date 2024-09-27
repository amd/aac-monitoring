#!/bin/bash
#================================================================
#   Script by AMD
#================================================================
#%
#%  DESCRIPTION
#%  This script for install aac observabality stack on Ubuntu 22.04.3 LTS
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

set -e

PROMETHEUS_INSTALLER="kube-prometheus-stack"
PROMETHEUS_NAMESPACE="aac-monitoring"
INGRESS_CONTROLLER="ingress-nginx"
INGRESS_NAMESPACE="ingress-nginx"
SITE_NAME=""
prometheus_username=""
prometheus_password=""
rocm_rdc_image_tag=""
storage_class=""

execute_deployment(){
  validate_helm
  # Get the kube-prometheus-stack installation YAML

  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update

  read -r NAME CHART_VERSION APP_VERSION <<< $(helm search repo ${PROMETHEUS_INSTALLER} | awk 'NR==2 {print $1, $2, $3}')
  mkdir -p ./kubernetes/prometheus/controller/prometheus/manifests/

  # helm show values prometheus-community/kube-prometheus-stack > values.yaml
  # helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --values values.yaml --namespace aac-monitoring

  helm template ${PROMETHEUS_INSTALLER} kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --version ${CHART_VERSION} \
  --namespace ${PROMETHEUS_NAMESPACE} \
  --values ../k8s-prometheus/kube-prometheus-stack-values.yaml \
  --include-crds \
  > ./kubernetes/prometheus/controller/prometheus/manifests/kube-prometheus-stack.${APP_VERSION}.yaml

  # Deploy the Kube Prometheus Stack

  if ! kubectl get namespace $PROMETHEUS_NAMESPACE > /dev/null 2>&1; then
    echo "Namespace $PROMETHEUS_NAMESPACE does not exist. Creating..."
    kubectl create namespace $PROMETHEUS_NAMESPACE
  else
    echo "Namespace $PROMETHEUS_NAMESPACE already exists."
  fi

  if [ -n "$storage_class" ]; then
    sed -i "s/<storage_class_name>/$storage_class/g" ../k8s-prometheus/kube-prometheus-stack-values.yaml
  fi
  helm upgrade --install ${PROMETHEUS_INSTALLER} prometheus-community/kube-prometheus-stack \
  --values ../k8s-prometheus/kube-prometheus-stack-values.yaml --namespace ${PROMETHEUS_NAMESPACE}

  # alertmanagers.monitoring.coreos.com" is invalid: metadata.annotations: Too long: must have at most 262144 bytes
  #kubectl apply -f ./kubernetes/prometheus/controller/prometheus/manifests/kube-prometheus-stack.${APP_VERSION}.yaml

  # Get the nginx-ingress controller installation YAML
  helm repo add ${INGRESS_CONTROLLER} https://kubernetes.github.io/ingress-nginx
  helm repo update

  read -r NAME CHART_VERSION APP_VERSION <<< $(helm search repo ${INGRESS_CONTROLLER} | awk 'NR==2 {print $1, $2, $3}')
  mkdir -p ./kubernetes/ingress/controller/nginx/manifests/

  # helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx > nginx-ingress-values.yaml
  helm template ${INGRESS_CONTROLLER} ${INGRESS_CONTROLLER} \
  --repo https://kubernetes.github.io/ingress-nginx \
  --version ${CHART_VERSION} \
  --namespace ${INGRESS_NAMESPACE} \
  --values ../nginx-ingress/nginx-ingress-values.yaml \
  --include-crds \
  > ./kubernetes/ingress/controller/nginx/manifests/nginx-ingress.${APP_VERSION}.yaml

  # Deploy the Nginx Ingress Controller

  if ! kubectl get namespace $INGRESS_NAMESPACE > /dev/null 2>&1; then
    echo "Namespace $INGRESS_NAMESPACE does not exist. Creating..."
    kubectl create namespace $INGRESS_NAMESPACE
  else
    echo "Namespace $INGRESS_NAMESPACE already exists."
  fi

  helm upgrade --install ${INGRESS_CONTROLLER} ${INGRESS_CONTROLLER}/${INGRESS_CONTROLLER} \
  --values ../nginx-ingress/nginx-ingress-values.yaml --namespace ${INGRESS_NAMESPACE}
  #--create-namespace

  #kubectl apply -f ./kubernetes/ingress/controller/nginx/manifests/nginx-ingress.${APP_VERSION}.yaml
  # Validate presence of nginx-ingress-tls and prometheus-basic-auth secrets

  if ! kubectl get secret nginx-ingress-tls --namespace "$PROMETHEUS_NAMESPACE" &> /dev/null; then
    kubectl create secret tls nginx-ingress-tls --cert=../certs/${SITE_NAME}.crt --key=../certs/${SITE_NAME%%.*}.key -n $PROMETHEUS_NAMESPACE
  fi
  if ! kubectl get secret prometheus-basic-auth --namespace "$PROMETHEUS_NAMESPACE" &> /dev/null; then
    if [ ! -f auth ]; then
      check_htpasswd_installed
      echo "$prometheus_password" | htpasswd -c -i auth $prometheus_username
    fi
    kubectl create secret generic prometheus-basic-auth --from-file=auth -n $PROMETHEUS_NAMESPACE
  fi

  echo "Waiting for nginx-ingress-controller pod to come up ...."
  sleep 30
  sed -i "s/'\*'/'$SITE_NAME'/g" ../nginx-ingress/ingress.yaml
  kubectl apply -f ../nginx-ingress/ingress.yaml

  # Make sure you build the docker image prior to execute the following deployment"
  sed -i "s|image: .*|image: $rocm_rdc_image_tag|g" ../k8s-daemonset/rocm-rdc-daemonset.yaml
  echo "Container image updated to - $rocm_rdc_image_tag"
  
  echo "Starting deployment of rocm-rdc, fluent-bit and node-health stack"
  kubectl apply -f  ../k8s-daemonset

  PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx | awk '/443:/ {split($5, a, ","); for (i in a) if (a[i] ~ /^443:/) {split(a[i], p, ":"); split(p[2], port, "/"); print port[1];}}')

  echo "DEPLOYMENT COMPLETED ....."
  echo "Promethues URL: https://${SITE_NAME}:${PORT}/prometheus with credentials $prometheus_username|$prometheus_password"
}

execute_undeployment(){
  validate_helm
  kubectl delete -f  ../k8s-daemonset
  # Undeploy kube-prometheus-stack
  if helm ls -n ${PROMETHEUS_NAMESPACE} | grep -q 'deployed'; then
    helm uninstall ${PROMETHEUS_INSTALLER} -n ${PROMETHEUS_NAMESPACE}
    kubectl delete crd alertmanagerconfigs.monitoring.coreos.com
    kubectl delete crd alertmanagers.monitoring.coreos.com
    kubectl delete crd podmonitors.monitoring.coreos.com
    kubectl delete crd probes.monitoring.coreos.com
    kubectl delete crd prometheusagents.monitoring.coreos.com
    kubectl delete crd prometheuses.monitoring.coreos.com
    kubectl delete crd prometheusrules.monitoring.coreos.com
    kubectl delete crd scrapeconfigs.monitoring.coreos.com
    kubectl delete crd servicemonitors.monitoring.coreos.com
    kubectl delete crd thanosrulers.monitoring.coreos.com
  fi

  # Undeploy nginx-ingress controller
  if helm ls -n ${INGRESS_NAMESPACE} | grep -q 'deployed'; then
    #kubectl delete pod kube-prometheus-stack-admission-create-l2xfs --grace-period=0 --force --namespace aac-monitoring
    kubectl delete -f ../nginx-ingress/ingress.yaml
    kubectl delete secret nginx-ingress-tls --namespace "$PROMETHEUS_NAMESPACE"
    kubectl delete secret prometheus-basic-auth --namespace "$PROMETHEUS_NAMESPACE"
    helm uninstall ${INGRESS_CONTROLLER} -n ${INGRESS_NAMESPACE}
  fi

  # Cleanup
  rm -rf auth
  rm -rf ./kubernetes
}

check_htpasswd_installed() {
    if ! command -v htpasswd &> /dev/null
    then
        echo "htpasswd could not be found"
        echo "Installing htpasswd on Debian-based system..."
        sudo apt-get update
        sudo apt-get install -y apache2-utils
    else
        echo "htpasswd is installed"
    fi
}

usage(){
  echo ""
  echo "-- Deploy AAC monitoring framework using kube-prometheus-stack and nginx ingress controller --"
  echo "Usage:$0 -s <site_name> -u <prometheus_username> -p <prometheus_password> [options] [flags]"
  echo "[OPTIONS]"
  echo "  -s|--site Specify GPU cluster site name (mandatory)"
  echo "  -i|--image ROCm/RDC docker image tag with repo details (mandatory for deployment)"
  echo "  -u|--username Specific prometheus enabled basic authentication username, default: aac-prometheus"
  echo "  -p|--password Specific prometheus enabled basic authentication password, default: aac_1234"
  echo "  -c|--storageclass Specific stoarge class to provision persistent volume claim for Prometheus TSDB "
  echo "[FLAGS]"
  echo "  --deploy: Install aac monitoring framework and nginx ingress controller using helm"
  echo "  --undeploy: Uninstall aac moitoring framework and nginx ingress controller using helm"
  echo "  -h, --help: For help"
  echo ""
}

parse_args(){
  unset SITE_NAME
  local deployment_requested=false
  local undeployment_requested=false

  while test $# -gt 0
  do
    case "$1" in
    -s|--site)
      shift
      SITE_NAME=$(echo "${1,,}")
      ;;
    -i|--image)
      shift
      rocm_rdc_image_tag=$(echo "${1,,}")
      ;;
    -u|--username)
      shift
      prometheus_username=$(echo "${1,,}")
      ;;
    -p|--password)
      shift
      prometheus_password=$(echo "${1,,}")
      ;;
    -c|--storageclass)
      shift
      storage_class=$(echo "${1,,}")
      ;;
    --deploy)
      deployment_requested=true
      ;;
    --undeploy)
      undeployment_requested=true
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

  if [ -z "$SITE_NAME" ]; then
    echo "Error: Site name must be provided with -s or --site."
    usage
    exit 1
  fi

  if [ -z "$storage_class" ]; then
    echo "Error: Storage class must be provided with -c or --storageclass."
    usage
    exit 1
  fi

  if ! $deployment_requested && ! $undeployment_requested; then
    echo "Error: No operation specified. Use --deploy or --undeploy."
    usage
    exit 1
  fi

  if [[ -z "$rocm_rdc_image_tag" && $deployment_requested ]]; then
    echo "Error: ROCm/RDC Image tag with repository name must be provided with -i or --image."
    usage
    exit 1
  fi

  # Check for certs folder and it's contents
  if [ -d "../certs" ]; then
    crtFile=(`find ../certs -maxdepth 1 -name "*.crt" | wc -l`)
    keyFile=(`find ../certs -maxdepth 1 -name "*.key" | wc -l`)
    if [[ $crtFile -eq 0 || $keyFile -eq 0 ]]; then
      echo "Error: No TLS certificate or private key found."
      usage
      exit 1
    fi
  fi

  if [ -z "$prometheus_username" ]; then
    prometheus_username="aac-prometheus"
  fi

  if [ -z "$prometheus_password" ]; then
    prometheus_password="aac_1234"
  fi
  
  if $deployment_requested; then
    execute_deployment
  fi

  if $undeployment_requested; then
    execute_undeployment
  fi
}

# Install Helm

# Function to install Helm on Linux
install_helm_linux() {
  echo "Installing Helm for Linux..."
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
}

# Function to install Helm on macOS
install_helm_mac() {
  echo "Installing Helm for macOS..."
  brew install helm
}

validate_helm(){

  # Check if Helm is installed by looking for its version
  if helm version > /dev/null 2>&1; then
    echo "Helm is already installed."
  else
    echo "Helm is not installed."
    # Detect the operating system
    case "$(uname -s)" in
        Linux*)     install_helm_linux;;
        Darwin*)    install_helm_mac;;
        *)          echo "Unsupported OS"; exit 1;;
    esac
  fi

  # Verify installation
  if helm version > /dev/null 2>&1; then
    echo "Helm installation was successful."
  else
    echo "Helm installation failed."
  fi
}

parse_args "$@"

set +e