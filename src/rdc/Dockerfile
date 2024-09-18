# Stage 1: Build Environment
FROM ubuntu:22.04 as builder

ARG series

RUN if [ -z "$series" ] ; then echo "Error: No series argument provided" && exit 1; fi

USER 0

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true
ENV BUILD_TYPE=RelWithDebInfo
ENV ROCM_DIR=/opt/rocm
ENV JOB_NAME=compute-rocm-dkms-no-npi-hipclang
ENV AMDGPU_REPO_DEB=amdgpu-install-internal_6.3-22.04-1_all.deb

# Set up apt repos and install dependencies
RUN echo 'Acquire::https { Verify-Peer false; Verify-Host false; }' > /etc/apt/apt.conf.d/99verify-ssl
RUN apt update -y && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ca-certificates \
  gnupg \
  gpg-agent \
  software-properties-common && \
  update-ca-certificates

RUN apt install -y jq \
  nodejs \
  wget \
  curl \
  python3 \
  python3-pip \
  file && \
  add-apt-repository -y ppa:apt-fast/stable && \
  apt update -y && \
  apt install -y apt-fast

RUN rm /etc/apt/apt.conf.d/99verify-ssl

RUN wget "http://artifactory-cdn.amd.com/artifactory/list/amdgpu-deb/$AMDGPU_REPO_DEB" -O /tmp/$AMDGPU_REPO_DEB
RUN apt-fast install -y "/tmp/$AMDGPU_REPO_DEB"

# Get latest build number
RUN echo 'Acquire::https { Verify-Peer false; Verify-Host false; }' > /etc/apt/apt.conf.d/99verify-ssl
RUN curl -Ls "http://rocm-ci.amd.com/job/${JOB_NAME}/lastStableBuild/api/json?depth=1" -o /tmp/build_info.json
RUN cat /tmp/build_info.json | jq '.actions[] | .buildsByBranchName."refs/remotes/origin/amd-master".buildNumber | select(. != null)' > /tmp/build_num.txt
RUN BUILD_NUM=$(cat /tmp/build_num.txt) && \
  # RUN BUILD_NUM=14316 && \
  echo "BUILD_NUM=$BUILD_NUM" >> "/tmp/.github_env" && \
  echo "BUILD_NUM=$BUILD_NUM" >> "/tmp/.github_output" && \
  amdgpu-repo --amdgpu-build=2038746 --rocm-build=$JOB_NAME/$BUILD_NUM && \
  apt-fast update -y

#RUN amdgpu-repo --amdgpu-build=1788030 --rocm-build=compute-rocm-dkms-no-npi-hipclang/14195
# Install apt packages
RUN apt-fast install -y \
  rocm-core \
  amd-smi-lib \
  #rocblas \
  #rocblas-dev \
  rocm-developer-tools \
  rocm-device-libs \
  rocm-smi-lib \
  rocprofiler-dev \
  build-essential \
  libcap-dev \
  rdc \
  kmod

RUN rm /etc/apt/apt.conf.d/99verify-ssl

# Clean up
RUN apt autoremove && apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------- Local cleanup for sudo apt update - sudo rm  /etc/apt/sources.list.d/rocm.list
# Stage 2: Final Environment
FROM ubuntu:22.04

ARG series

COPY --from=builder /opt /opt
COPY --from=builder /usr /usr
COPY --from=builder /etc /etc

RUN apt update -y && apt install -y supervisor && \
  apt autoremove && apt clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY sudo-nopasswd /etc/sudoers.d/sudo-nopasswd
RUN useradd --create-home -G sudo,video --shell /bin/bash rocm-user

RUN pip install prometheus_client Flask twilio
COPY rdc_fields_list /usr/src/app/rdc_fields_list

RUN series_lower=$(echo $series | tr '[:upper:]' '[:lower:]'); \
  if [ "$series_lower" = "mi300" ]; then \
  echo "Appending additional fields for MI300" && \
  echo "RDC_FI_PCIE_BANDWIDTH\nRDC_FI_XGMI_0_READ_KB\nRDC_FI_XGMI_1_READ_KB\nRDC_FI_XGMI_2_READ_KB\nRDC_FI_XGMI_3_READ_KB\nRDC_FI_XGMI_4_READ_KB\nRDC_FI_XGMI_5_READ_KB\nRDC_FI_XGMI_6_READ_KB\nRDC_FI_XGMI_7_READ_KB\nRDC_FI_XGMI_0_WRITE_KB\nRDC_FI_XGMI_1_WRITE_KB\nRDC_FI_XGMI_2_WRITE_KB\nRDC_FI_XGMI_3_WRITE_KB\nRDC_FI_XGMI_4_WRITE_KB\nRDC_FI_XGMI_5_WRITE_KB\nRDC_FI_XGMI_6_WRITE_KB\nRDC_FI_XGMI_7_WRITE_KB" >> /usr/src/app/rdc_fields_list; \
  else \
  echo "No additional fields appended"; \
  fi

RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY node_health.sh /usr/local/bin/node_health.sh
RUN chmod +x /usr/local/bin/node_health.sh
COPY node_health.py /usr/local/bin/node_health.py

WORKDIR /opt/rocm/libexec/rdc/python_binding
RUN sed -i "s/field_id = rdc.get_field_id_from_name(f)/field_id = rdc.get_field_id_from_name(str.encode(f))/" rdc_prometheus.py
COPY RdcReader.py /opt/rocm/libexec/rdc/python_binding
COPY rdc_prometheus.py /opt/rocm/libexec/rdc/python_binding


USER rocm-user
WORKDIR /home/rocm-user
ENV ROCM_PATH=/opt/rocm
ENV PATH=$ROCM_PATH/bin:$PATH

# sudo find / -name librdc_rocr.so 2>/dev/null
ENV LD_LIBRARY_PATH=/opt/rocm/lib/rdc
ENV RDC_LIB_DIR=/opt/rocm/lib/rdc

EXPOSE 5050 5051

CMD ["/usr/bin/supervisord"]