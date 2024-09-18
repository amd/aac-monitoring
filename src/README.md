# --------------- AAC Monitoring Framework Deployment -------------

The AAC Monitoring Framework leverages the capabilities of the ***ROCm Data Center (RDC) Tool*** to address key 
infrastructure challenges in managing AMD GPUs within cluster and datacenter environments by collecting GPU telemetry data.

***Framework Components:***
```
  1. Kube-Prometheus-Stack
  2. Nginx-Ingress-Controller
  3. Nginx Reverse Proxy Server / Load Balancer
  4. Grafana
  5. Fluent-bit
  6. RoCM/RDC
```
> [!NOTE]
> - Kube-Prometheus-Stack and Nginx-Ingress-Controller both are Kubernetes Operator framework deployed through ***helm***
> - The design did not consider Prometheus Federation due to concerns about `network latency`, `bandwidth throttling`, and `throughput challenges` across all the sites.
> - Communication between Grafana and Prometheus is secured with HTTPS (***TLS and Basic Authentication enabled***).

### Design Workflow:

![image](https://github.com/AMD-Accel-Cloud/AAC/assets/164095873/9f52d85e-faf8-4257-ab72-7128b4d77160)

### Installation Steps:

> [!IMPORTANT]
> - Prometheus and Grafana communicate over TLS. We have not enabled mutual TLS.
> - Site specific SSL certificates are placed under the ***certs*** folder.
> - Certs installation location:
>     - Nginx Ingress Controller TLS enabled through `kubernetes tls secret creation`
>     - Grafana SSL certs needs to be configured in `/etc/grafana/grafana.ini`.
>     - NGINX SSL certs needs to be configured in `/etc/nginx/sites-avaliable/<site_name>` and to be placed in `/etc/ssl/certs` folder.
>     - Prometheus listens over http behind K8s ingress controller.
> - Do not create additional k8s resources, here is the list of [improvements](#automation-improvements) have been incorporated through deployment script automation.

### Deployment
***Build rocm-rdc and node-health images***
  * Clone the repository.
  * Navigate to the `monitoring/rdc` folder.
  * List of supported RoCM/rdc GPU telemetry fields [here](#gpu-telemetry-fields), edit __rdc_fields_list__ file for additional fields if required.
  * Execute the following command based on the HW information to build the docker image, if required
      
  ```
  docker build -t amdaccelcloud/monitoring:rocm_rdc_3.0.0 --build-arg series=MI300 .
  docker push amdaccelcloud/monitoring:rocm_rdc_3.0.0
  ```
> [!NOTE]
> - Make sure, you have executed ***`docker login -u <username> -p <password>`*** command prior to push the image to __amdaccelcloud/monitoring__ repository
> - Currently supported series argument for docker build: `MI210` | `MI250` | `MI300`
> - Maintain the recommended build tag version; for __MI3X__: `amdaccelcloud/monitoring:rocm_rdc_3.0.0` and for __MI2X__: `amdaccelcloud/monitoring:rocm_rdc_2.0.0`
  * Navigate to the `monitoring/node_health` folder.
  * Execute the following command based to build the docker image, if required

  ```
  docker build -t amdaccelcloud/monitoring:node_health_1.0.0 .
  docker push amdaccelcloud/monitoring:node_health_1.0.0
  ```
***Deploy `Kube-Prometheus-Stack` and `Nginx-Ingress-Controller` with `fluentbit` `RoCM/rdc` and `node health` as kubernetes daemonset***
> [!WARNING]
> The deployment script execution will fail if the followings prerequisites are not fulfilled.
> - Add label `kubernetes.io/role=monitoring` to edge node.
> ```
> kubectl label nodes <node_name> kubernetes.io/role=monitoring
> ```
> - Get site specific SSL Certificate from [amd.service-now](https://amd.service-now.com/sp?id=ticket&table=sc_req_item&sys_id=6a6938ed1b941294df3c62c4bd4bcbfe&view=sp) by providing __csr__.
> ```
> openssl req -new -nodes -newkey rsa:2048 -keyout aac4.key -out aac4.amd.com.csr -config aac4-san.cnf
> ```
> - Create site specific certs folder under __certs__ directory and copy the TLS private key and cerificate files
> - Ensure NFS Server connectivity is established  from the edge node, as volumes are claimed through PVC for Prometheus TSDB.

***Execute the deployment script:***

```
./installer.sh --site <Site_Name> --deploy|--undeploy`
```
  
> [!CAUTION]
> If script execution fails, uninstall the complete monitoring stack by executing the same script with `--undeploy` flag prior to reinstall.

***Deploy Grafana in AWS EC2 Instance***
  * Navigate to the monitoring/grafana folder.
  * Run the shell script: `./install_grafana.sh`
  * Upload dashboard JSON content from the monitoring/grafana/dashboard folder to the Grafana UI.

### Automation Improvements
  * RoCM/rdc binary updated to latest stable [build](http://rocm-ci.amd.com/job/compute-rocm-dkms-no-npi-hipclang/14776/) version __6.3__
  * Docker registry secret, Prometheus basic auth and NGINX Ingress Controller site specific TLS certificates creation.
  * Docker build args has been enabled to provide GPU hardware series information.
  * GPU Telemetry Fields getting populated dynamically based on the GPU hardware information - incorporated in DockerFile.
  * Container image tag updated based on the GPU hardware information based on __site mapping__ file.
  * Update of Storage Class Driver information under Prometheus Storage Spec.

### GPU Telemetry Fields
  ***MI200 | MI210 | MI250:***
  `RDC_FI_GPU_COUNT` `RDC_FI_DEV_NAME` `RDC_FI_GPU_MEMORY_USAGE` `RDC_FI_GPU_MEMORY_TOTAL` `RDC_FI_POWER_USAGE` `RDC_FI_GPU_CLOCK` `RDC_FI_MEM_CLOCK`
  `RDC_FI_GPU_UTIL` `RDC_FI_GPU_TEMP` `RDC_FI_MEMORY_TEMP` `RDC_FI_PCIE_TX` `RDC_FI_PCIE_RX` `RDC_FI_ECC_XGMI_WAFL_SEC` `RDC_FI_ECC_XGMI_WAFL_DED`
  
  ***MI300***: additional fields
  `RDC_FI_PCIE_BANDWIDTH` `RDC_FI_XGMI_[0-7]_READ_KB` `RDC_FI_XGMI_[0-7]_WRITE_KB`

> [!TIP]
> To enhance the `aac-monitoring` stack functionlity fork the repo or create a feature branch.
> Verify the deployment by using the following commands.
> ```
> kubectl get all -n aac-monitoring
> kubectl get all -n ingress-nginx
> kubectl get pods -n aac-monitoring
> 
> kubectl exec -it <rocm_rdc_daemonset_pod> -n aac-monitoring bash
> - supervisortcl status [all the processes should be RUNNING state]
> - curl localhost:5050 [for RoCM/rdc metrics]
> - curl localhost:5051/node_health [for node health metrics]
> 
> kubectl exec -it <node_health_daemonset_pod> -n aac-monitoring bash
> - curl localhost:5051/node_health [for node health metrics from head node]
>
> kubectl get svc/ingress-nginx-controller -n ingress-nginx
> - TLS enabled, only PORT 443 is allowed.
> - Add nodeport and site information to create new datasource in grafana.
>
> Prometheus TSDB URL
> https://<Node_IP>:<NodePort>/prometheus
> ```
