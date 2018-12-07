#!/bin/bash

mkdir -p /opt/monitoring/jmx_exporter
cd /opt/monitoring/jmx_exporter

wget https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.3.0/jmx_prometheus_javaagent-0.3.0.jar
wget https://raw.githubusercontent.com/prometheus/jmx_exporter/master/example_configs/cassandra.yml
echo 'JVM_OPTS="$JVM_OPTS -javaagent:/opt/monitoring/jmx_exporter/jmx_prometheus_javaagent-0.3.0.jar=7070:/opt/monitoring/jmx_exporter/cassandra.yml"' >> /etc/cassandra/conf/cassandra-env.sh

service cassandra stop
service cassandra start
