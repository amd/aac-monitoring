# AMD Accelerator Cloud (AAC) Monitoring Framework
The AAC monitoring framework is an easy-to-use framework to monitor data center environment with clusters of AMD GPUs. The framework collects GPU telemetry data which can be visualized in dashboards to monitor the health, utilization and several key metrics of GPU nodes. The AAC Monitoring Framework leverages the capabilities of [ROCm Data Center Tool](https://rocm.docs.amd.com/projects/rdc) to address key infrastructure challenges in managing AMD GPUs within cluster and datacenter environments.

***Key Components:***
```
  1. Kube-Prometheus-Stack
  2. Nginx-Ingress-Controller
  3. Grafana
  4. Nginx Reverse Proxy Server and Load Balancer
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
> - SSL certificates needs to be placed under ***monitoring/src/certs*** folder.
> - Certs installation location:
>     - Nginx Ingress Controller TLS enabled through `kubernetes tls secret creation` using ***certs*** folder.
>     - If TLS requires to be enabled for Grafana, SSL certs needs to be configured in `/etc/grafana/grafana.ini`. ***[optional]***
>     - Nginx Proxy Server acts as reverse proxy for Grafana and SSL certs needs to be configured in `/etc/nginx/sites-avaliable/<site_name>` configuration file and to be placed under ***`/etc/ssl/certs`*** folder.
>     - Prometheus listens over http behind K8s Nginx ingress controller.
>     - Grafana listens over http behind NGINX reverse proxy server.
> - Do not create additional k8s resources, here is the list of [improvements](#automation-improvements) have been incorporated through deployment script automation.

### Deployment
***Build rocm-rdc and node-health images***
  * Complete all the prerequisites steps mentioned above.
  * Clone the repository.
  * Navigate to the `monitoring/src/rdc` folder.
  * List of supported RoCM/rdc GPU telemetry fields [here](#gpu-telemetry-fields), edit __rdc_fields_list__ file for additional fields if required.
  * Execute the following command based on the HW information to build the docker image, if required
      
  ```
  docker login -u <username> -p <password>
  docker build -t <repo>:rocm_rdc_3.0.0 --build-arg series=MI300 .
  docker push <repo>:rocm_rdc_3.0.0
  ```
> [!NOTE]
> - Supported series argument for docker build: `MI210` | `MI250` | `MI300`
> - Recommended build tag version; for __MI3x__: `<repo>:rocm_rdc_3.0.0` and for __MI2x__: `<repo>:rocm_rdc_2.0.0`
> - GPU Telemetry Fields getting populated dynamically based on the GPU hardware information - incorporated in DockerFile.
  * Navigate to the `monitoring/src/node_health` folder.
  * Execute the following command based to build the docker image, if required

  ```
  docker build -t <repo>:node_health_1.0.0 .
  docker push <repo>:node_health_1.0.0
  ```
***Deploy `Kube-Prometheus-Stack` and `Nginx-Ingress-Controller` with `fluentbit` `RoCM/rdc` and `node health` as kubernetes daemonset***
> [!WARNING]
> The script execution will fail if the followings prerequisites are not fulfilled.
> - Add label `kubernetes.io/role=monitoring` to management or edge node, where monitoring stack needs to be deployed.
> ```
> kubectl label nodes <node_name> kubernetes.io/role=monitoring
> ```
> - Generate TLS/SSL Certificate for ***kubernetes nginx ingress controller***.
> ```
> #== generate a self-signed certificate ==#
> openssl req -new -newkey rsa:2048 -nodes -keyout mydomain.key -out mydomain.csr -subj "/C=<CountryName>/ST=<StateOrProvinceName>/L=<Locality>/O=<Organization>/OU=<OrganizationalUnit>/CN=<CommonName>"
> openssl x509 -req -days 365 -in mydomain.csr -signkey mydomain.key -out mydomain.crt
> ```
> - Copy the generated TLS private key and cerificate file under  __certs__ directory.
> - If using NFS as storage class driver for kubernetes, ensure NFS Server connectivity is established from the edge or management node, as volumes are claimed through PVC for Prometheus TSDB.

***Execute the deployment script:***
* Navigate to the `monitoring/src/helm` folder and execute the following command
```
./installer.sh -s <site_name> -i <repo/image_tag> -u <prometheus_username> -i <prometheus_password> --deploy|--undeploy`
```
  
> [!CAUTION]
> If script execution fails, uninstall the complete monitoring stack by executing the same script with `--undeploy` flag prior to reinstall. **Namespaces** won't be deleted. For more information about command usage: ***./installer.sh -h***

***Deploy Grafana***
  * Navigate to the `monitoring/src/grafana` folder.
  * Generate TLS certificate as mentioned [above](#deployment) for Nginx reverse proxy server and keep the cert and private key under /etc/ssl/certs directory as nginx.crt and nginx.key.
  * Run the shell script: `./setup.sh --install|uninstall`
  * Upload dashboard JSON content from the  `monitoring/src/grafana/dashboard/<MI2|3x>` folder based on the GPU hardware information to the Grafana UI.

### Automation Improvements
  * RoCM/rdc binary updated to latest stable version __6.2.1__
  * Kube-Prometheus-Stack and Nginx Ingress controller updated to version __v0.76.1__ and __1.11.2__
  * Docker registry, Prometheus basic auth, NGINX Ingress Controller and Reverse Proxy server TLS secret creation.
  * Docker build args has been enabled to provide GPU hardware series information.
  * GPU Telemetry Fields getting populated dynamically based on the GPU hardware information.
  * Update of Storage Class Driver information for Prometheus Storage Spec.

### GPU Telemetry Fields
  ***MI200 | MI210 | MI250:***
  `RDC_FI_GPU_COUNT` `RDC_FI_DEV_NAME` `RDC_FI_GPU_MEMORY_USAGE` `RDC_FI_GPU_MEMORY_TOTAL` `RDC_FI_POWER_USAGE` `RDC_FI_GPU_CLOCK` `RDC_FI_MEM_CLOCK`
  `RDC_FI_GPU_UTIL` `RDC_FI_GPU_TEMP` `RDC_FI_MEMORY_TEMP` `RDC_FI_PCIE_TX` `RDC_FI_PCIE_RX` `RDC_FI_ECC_XGMI_WAFL_SEC` `RDC_FI_ECC_XGMI_WAFL_DED`
  
  ***MI300***: additional fields
  `RDC_FI_PCIE_BANDWIDTH` `RDC_FI_XGMI_[0-7]_READ_KB` `RDC_FI_XGMI_[0-7]_WRITE_KB`

> [!TIP]
> To enhance the `aac-monitoring` stack functionlity, fork the repo or create a feature branch and raise bug if functionality fails or broken.
> Verify the deployment by using the following commands.
> ```
> kubectl get all -n aac-monitoring
> kubectl get all -n ingress-nginx
> kubectl get pods -n aac-monitoring
> 
> kubectl exec -it <rocm_rdc_daemonset_pod> -n aac-monitoring bash
> - supervisortcl status [all the processes should be RUNNING state]
> - curl localhost:5050 [for ROCm/rdc metrics]
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
