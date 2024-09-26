# rocm-terminal --> rocm-dev --> rocm-libs
FROM rocm/rocm-terminal:6.2.1

ARG series

RUN if [ -z "$series" ] ; then echo "Error: No series argument provided" && exit 1; fi

USER 0

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true
ENV BUILD_TYPE=RelWithDebInfo
ENV ROCM_DIR=/opt/rocm

# Install apt packages
RUN apt-get update && apt-get upgrade -y && \
 DEBIAN_FRONTEND=noninteractive apt-get install -y \
 amd-smi-lib \
 rocm-developer-tools \
 rocm-device-libs \
 rocm-smi-lib \
 rocprofiler-dev \
 libcap-dev \
 rdc

# Clean up
RUN apt autoremove && apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt update -y && apt install -y supervisor && \
  apt autoremove && apt clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN pip install prometheus_client Flask twilio
COPY rdc_fields_list /usr/src/app/rdc_fields_list

RUN series_lower=$(echo $series | tr '[:upper:]' '[:lower:]'); \
  if [ "$series_lower" = "mi300" ]; then \
  echo "Appending additional fields for MI300" && \
  echo "\nRDC_FI_PCIE_BANDWIDTH\nRDC_FI_XGMI_0_READ_KB\nRDC_FI_XGMI_1_READ_KB\nRDC_FI_XGMI_2_READ_KB\nRDC_FI_XGMI_3_READ_KB\nRDC_FI_XGMI_4_READ_KB\nRDC_FI_XGMI_5_READ_KB\nRDC_FI_XGMI_6_READ_KB\nRDC_FI_XGMI_7_READ_KB\nRDC_FI_XGMI_0_WRITE_KB\nRDC_FI_XGMI_1_WRITE_KB\nRDC_FI_XGMI_2_WRITE_KB\nRDC_FI_XGMI_3_WRITE_KB\nRDC_FI_XGMI_4_WRITE_KB\nRDC_FI_XGMI_5_WRITE_KB\nRDC_FI_XGMI_6_WRITE_KB\nRDC_FI_XGMI_7_WRITE_KB" >> /usr/src/app/rdc_fields_list; \
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