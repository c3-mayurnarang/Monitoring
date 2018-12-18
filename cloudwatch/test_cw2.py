#!/usr/bin/python
from time import sleep
import boto3
import os
from datetime import datetime
from subprocess import Popen, PIPE, call
from prometheus_client import start_http_server, Gauge

CLIENT = boto3.client('cloudwatch', region_name='us-west-2')
log_file = '/opt/monitoring/test_cw/test_cw.log'
regions = ['us-east-1']
start_http_server(7080)
gauge = Gauge('elb', 'Certificate expiration for each load balancer', ['name'])

while True:

  command = "df | awk '{print $1,$2}'"
  process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
  stdout, stderr = process.communicate()
  return_code = process.returncode

  try:
    if return_code == 0:
      out = stdout.split('\n')
      for line in out:
        line = line.split()
        if len(line) > 1:
          a = line[0]
          b = line[1]
          if b.isdigit():
            b = int(b)
            gauge.labels(a).set(b)
  except Exception as e:
    with open(log_file, "a") as log:
      log.write(str(datetime.now()) + ' ' + str(e) + '\nreturn_code:\n' + str(return_code) + '\nstdout:\n' + stdout + '\nstderr:\n' + stderr + '\n\n')

  sleep(30)
