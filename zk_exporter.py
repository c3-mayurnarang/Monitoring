#!/usr/bin/python
# prometheus exporter to report zookeeper disk
# Requirement: pip install prometheus_client
# Nick Cogswell 11/9/18

import os
import subprocess
from time import sleep
from prometheus_client import start_http_server, Gauge
from datetime import datetime

log_file = '/opt/monitoring/master_exporter/master_exporter.log'
ZK_LOG_DIR = '/var/zk'
DATASOURCE = 'paas-data'

if __name__ == "__main__":
  gauge = Gauge('zookeeper_states', 'The current state of Zookeeper', ['zk_state', 'keyspace'])
  start_http_server(7071)

  while True:
    disk = os.statvfs(ZK_LOG_DIR)
    percent = (disk.f_blocks - disk.f_bfree) * 100 / (disk.f_blocks - disk.f_bfree + disk.f_bavail) + 1
    avail = (disk.f_blocks - disk.f_bfree) * disk.f_bsize

    gauge.labels('zk_log_dir_pct', DATASOURCE).set(percent)
    gauge.labels('zk_log_dir_avail', DATASOURCE).set(avail)

    sss = subprocess.Popen(['/bin/echo mntr | /usr/bin/nc localhost 2181'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    r = sss.stdout.readlines()
    for i in r:
        mm = i.decode('utf-8').strip().split('\t')
        if mm[1].isdigit():
          gauge.labels(mm[0], DATASOURCE).set(int(mm[1]))
    sleep(30)
