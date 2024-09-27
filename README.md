# AMD Accelerator Cloud (AAC) Monitoring Framework
The AAC Monitoring Framework is a user-friendly solution designed to monitor data center environments equipped with clusters of AMD GPUs. It gathers GPU telemetry data, enabling visualization of health, utilization, and various key metrics of GPU nodes through dashboards. This framework leverages the [ROCm Data Center Tool](https://rocm.docs.amd.com/projects/rdc) to tackle critical infrastructure challenges associated with managing AMD GPUs in cluster and data center environments.

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
> - Kube-Prometheus-Stack and Nginx-Ingress-Controller are deployed using the Kubernetes Operator framework via ***Helm***.
> - Prometheus Federation was excluded from the design due to potential `network latency`, `bandwidth throttling`, and `throughput challenges` across all sites.
> - Grafana and Prometheus communicate securely over HTTPS, utilizing ***TLS and Basic Authentication***.

### Design Workflow:

![image](https://github.com/AMD-Accel-Cloud/AAC/assets/164095873/9f52d85e-faf8-4257-ab72-7128b4d77160)

### Installation Steps:

> [!IMPORTANT]
> - Communication between Prometheus and Grafana is secured via TLS, but mutual TLS is not enabled.
> - SSL certificates should be placed in the ***monitoring/src/certs*** folder.
> - Certificate installation locations:
>     - Nginx Ingress Controller TLS is enabled through kubernetes tls secret creation using the __certs__ folder.
>     - If TLS is required for Grafana, configure SSL certificates in `/etc/grafana/grafana.ini`. __[optional]__
>     - After installing the Nginx proxy server for Grafana, create a site-specific configuration at `/etc/nginx/sites-available/<site_name>` and copy the contents from `monitoring/src/grafana/nginx.conf` to __<site_name>__.
>      
>        ![image](https://github.com/user-attachments/assets/5a941ec3-c9dc-428e-877a-96831d5122a9)
>     - Nginx Proxy Server SSL certificates should be placed in the `/etc/ssl/certs` folder.
>     - Prometheus listens over HTTP behind the Kubernetes Nginx Ingress Controller.
>     - Grafana listens over HTTP behind the Nginx reverse proxy server.
> - Avoid creating additional Kubernetes resources; [improvements](#automation-improvements) have been incorporated through deployment script automation.

### Deployment
***Build rocm-rdc and node-health images***
  * Complete all the prerequisite steps outlined above.
  * Clone the repository.
  * Navigate to the `monitoring/src/rdc` directory.
  * Review the list of supported ROCm/RDC GPU telemetry fields [here](#gpu-telemetry-fields), and update the __rdc_fields_list__ file to include additional fields if needed.
  * Run the appropriate `docker build` command based on the hardware information to build the Docker image, if required.

  ```
  docker login -u <username> -p <password>
  docker build -t <repo>:rocm_rdc_3.0.0 --build-arg series=MI300 .
  docker push <repo>:rocm_rdc_3.0.0
  ```
> [!NOTE]
> - Supported series arguments for Docker build: `MI210`, `MI250`, `MI300`.
> - Recommended build tag versions: For __MI3x__ use `<repo>:rocm_rdc_3.0.0`, and for __MI2x__ use `<repo>:rocm_rdc_2.0.0`.
> - GPU Telemetry Fields are dynamically populated based on the GPU hardware information, as implemented in the Dockerfile.
  * Navigate to the `monitoring/src/node_health` directory.
  * Run the following command based to build the docker image, if required.

  ```
  docker build -t <repo>:node_health_1.0.0 .
  docker push <repo>:node_health_1.0.0
  ```
***Deploy `Kube-Prometheus-Stack`, `Nginx-Ingress-Controller`, `FluentBit`, `RoCM/RDC`, and `Node Health` as Kubernetes DaemonSets***
> [!WARNING]
> __The script will fail if the following prerequisites are not met:__
> - Add the label `kubernetes.io/role=monitoring` to the management or edge node where the monitoring stack will be deployed.
> ```
> kubectl label nodes <node_name> kubernetes.io/role=monitoring
> ```
> - Generate a TLS/SSL certificate for the ***Kubernetes Nginx Ingress Controller*** if needed, or use existing certificates.
> ```
> #== generate a self-signed certificate ==#
> openssl req -new -newkey rsa:2048 -nodes -keyout mydomain.key -out mydomain.csr -subj "/C=<CountryName>/ST=<StateOrProvinceName>/L=<Locality>/O=<Organization>/OU=<OrganizationalUnit>/CN=<CommonName>"
> openssl x509 -req -days 365 -in mydomain.csr -signkey mydomain.key -out mydomain.crt
> ```
> - Place the generated TLS private key and certificate file in the __certs__ directory.
> - If using NFS as a storage class driver for Kubernetes, ensure that NFS Server connectivity is established from the edge or management node, as volumes for Prometheus TSDB are claimed through PVC.
>   ```
>   Install NFS Client on monitoring node:
>   sudo apt-get update
>   sudo apt-get install nfs-common
>   ```
> - Update the container image tag for the node health DaemonSet in `monitoring/src/k8s-daemonset/node_health.yaml` as follows: __image: <repo/image>__
> - Update the base64-encoded Docker repository image pull secret in `monitoring/src/k8s-daemonset/secret.yaml` as follows: __.dockerconfigjson: <secret_here>__

***Execute the deployment script:***
* Navigate to the `monitoring/src/helm` directory and run the following command:
```
chmod +x installer.sh
./installer.sh -s <site_name> -i <repo/image_tag> -u <prometheus_username> -i <prometheus_password> --deploy|--undeploy`
```
  
> [!CAUTION]
> If the script execution fails, uninstall the entire monitoring stack by running the same script with the --undeploy flag before attempting to reinstall. __Namespaces will not be deleted__. For more information on command usage, use: ***./installer.sh -h***

***Deploy Grafana***
  * Navigate to the `monitoring/src/grafana` directory.
  * Generate a TLS certificate as described [above](#deployment) for the Nginx reverse proxy server, and place the certificate and private key in the `/etc/ssl/certs` directory as nginx.crt and nginx.key.
  * Run the setup script: `chmod +x setup.sh && ./setup.sh --install|uninstall`
  * Add a new Prometheus data source in the Grafana UI and fill in the fields as shown in the screenshot. Once completed, click "Test" to verify the connectivity.

    ![image](https://github.com/user-attachments/assets/75847e2f-e82a-4c76-ac45-4f186b567d1e)

  * Upload the dashboard JSON content from the `monitoring/src/grafana/dashboard/<MI2x|MI3x>` folder, based on the GPU hardware information, to the Grafana UI.

### Automation Improvements
  * Updated RoCM/RDC binary to the latest stable version __6.2.1__.
  * Updated Kube-Prometheus-Stack and Nginx Ingress Controller to versions __v0.76.1__ and __1.11.2__, respectively.
  * Added automation for Docker registry, Prometheus Basic Auth, NGINX Ingress Controller, and Reverse Proxy Server TLS secret creation.
  * Enabled Docker build arguments for specifying GPU hardware series information.
  * Dynamic population of GPU telemetry fields based on GPU hardware information.
  * Updated storage class driver information for Prometheus storage specification.

### GPU Telemetry Fields
  ***MI200 | MI210 | MI250:***
  `RDC_FI_GPU_COUNT` `RDC_FI_DEV_NAME` `RDC_FI_GPU_MEMORY_USAGE` `RDC_FI_GPU_MEMORY_TOTAL` `RDC_FI_POWER_USAGE` `RDC_FI_GPU_CLOCK` `RDC_FI_MEM_CLOCK`
  `RDC_FI_GPU_UTIL` `RDC_FI_GPU_TEMP` `RDC_FI_MEMORY_TEMP` `RDC_FI_PCIE_TX` `RDC_FI_PCIE_RX` `RDC_FI_ECC_XGMI_WAFL_SEC` `RDC_FI_ECC_XGMI_WAFL_DED`
  
  ***MI300***: additional fields `RDC_FI_PCIE_BANDWIDTH` `RDC_FI_XGMI_[0-7]_READ_KB` `RDC_FI_XGMI_[0-7]_WRITE_KB`

> [!TIP]
> To enhance the `aac-monitoring` stack functionlity, fork the repository or create a feature branch and report any bugs if functionality fails or is broken.
> Verify the deployment using the following commands:
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
