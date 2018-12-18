#!/usr/bin/python
# cloudwatch exporter for zookeepers
# exports dist space and data

import os
import subprocess
from time import sleep
from datetime import datetime
from subprocess import Popen, PIPE, call
import boto3

client = boto3.client('cloudwatch', region_name='us-west-2')
command = "hostname"
process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
stdout, stderr = process.communicate()
name = stdout.split('.')[0]
log_file = '/opt/monitoring/zk_cw/zk_cw.log'
ZK_LOG_DIR = '/var/zk'
DATASOURCE = 'paas-data'

def post(dims, value):
  dims.append({'Name':'Name','Value':name})
  client.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': 'zookeeper',
              'Dimensions': dims,
              'Timestamp': datetime.now(),
              'Value': value,
              'Unit': 'None',
              'StorageResolution': 60
          },
      ]
  )
  #print 'dims: ' + str(dims) + ' val: ' + str(value)

if __name__ == "__main__":
  while True:
    try:
      # Export file system usage
      command = "df -kT | awk '{print $1,$2,$6,$7}'"
      process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
      stdout, stderr = process.communicate()
      return_code = process.returncode

      if return_code == 0:
        out = stdout.split('\n')
        for line in out:
          line = line.split()
          if len(line) > 3:
            f = line[0]
            t = line[1]
            p = line[2][:-1]
            m = line[3]
            #print f + ' ' + t + ' ' + p + ' ' + m
            if t in ('ext4','xfs') and p.isdigit() and m not in ('/var/log/app','/opt/cass'):
              p = float(p)
              dims = [{'Name':'login_state','Value':'fs'},{'Name':'fs','Value':f},{'Name':'mountpoint','Value':m}]
              post(dims, p)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting fs usage' + str(e))

    # Export log usage
    disk = os.statvfs(ZK_LOG_DIR)
    percent = (disk.f_blocks - disk.f_bfree) * 100 / (disk.f_blocks - disk.f_bfree + disk.f_bavail) + 1
    dims = [{'Name':'zk_state','Value':'zk_log_dir_pct'}]
    post(dims, percent)

    # Export zk stats
    sss = subprocess.Popen(['/bin/echo mntr | /usr/bin/nc localhost 2181'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    r = sss.stdout.readlines()
    for i in r:
        try:
          mm = i.decode('utf-8').strip().split('\t')
          if mm[0] in ['zk_approximate_data_size', 'zk_max_latency']:
            if mm[1].isdigit():
              dims = [{'Name':'zk_state','Value':mm[0]}]
              post(dims, int(mm[1]))
        except Exception as e:
          with open(log_file, "a") as log:
            log.write(str(datetime.now()) + ': ' + str(i) + '\n' + str(e) + '\n')

    sleep(30)
