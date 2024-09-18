FROM python:3.9-slim

RUN apt-get update && apt-get install -y curl
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /
COPY node_health.sh /usr/local/bin/node_health.sh
RUN chmod +x /usr/local/bin/node_health.sh
COPY node_health.py /usr/local/bin/node_health.py

RUN pip install --trusted-host pypi.python.org Flask
EXPOSE 5051

CMD ["python", "/usr/local/bin/node_health.py"]