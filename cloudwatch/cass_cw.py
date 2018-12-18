#!/usr/bin/python
# cloudwatch exporter for cassandra isntances
# exports node laod, fs usage, and select stats from jvm exporter

import os
from subprocess import Popen, PIPE, call
from time import sleep
from datetime import datetime
import boto3

client = boto3.client('cloudwatch', region_name='us-west-2')
command = "hostname"
process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
stdout, stderr = process.communicate()
name = stdout.split('.')[0]
log_file = '/opt/monitoring/cass_cw/cass_cw.log'

def post(dims, value):
  dims.append({'Name':'Name','Value':name})
  '''
  client.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': 'cassandra',
              'Dimensions': dims,
              'Timestamp': datetime.now(),
              'Value': value,
              'Unit': 'None',
              'StorageResolution': 60
          },
      ]
  )
  '''
  print 'dims: ' + str(dims) + ' val: ' + str(value)

if __name__ == "__main__":
  while True:
    # Export node load15
    command = "cat /proc/loadavg | awk '{print $3}'"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    try:
      node_load = float(stdout)
      dims = [{'Name':'cass_state','Value':'node_load15'}]
      post(dims, node_load)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting node load\n' + str(e) + '\nstdout:\n' + str(stdout) + '\nstderr:\n' + str(stderr) + '\n\n')

    # Export file system usage
    command = "df -kT | awk '{print $1,$2,$6,$7}'"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    return_code = process.returncode
    try:
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
            if t in ('ext4','xfs') and p.isdigit():
              p = float(p)
              dims = [{'Name':'cass_state','Value':'fs'},{'Name':'fs','Value':f},{'Name':'mountpoint','Value':m}]
              post(dims, p)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting sys stats\n' + str(e))

    # Pull and export select JVM stats
    try:
      handle = open('jvm', 'r')
      for line in handle:
        if (line.startswith('jvm_memory_bytes_used') or
            line.startswith('jvm_memory_bytes_committed') or
            line.startswith('cassandra_clientrequest_latency') or
            line.startswith('cassandra_compaction_pendingtasks')):

          line = line.split()
          if len(line) > 1:
            temp = line[0]

            if '{' in temp:
              metric = temp[:temp.find('{')]
              dimensions = temp[temp.find('{')+1:-1]
            else:
              metric = temp
              dimensions = ''

            dimensions = dimensions.split(',')
            dims = [{'Name':'metric','Value':metric},{'Name':'Host','Value':'test-host-01'}]

            for dimension in dimensions:
              if '=' in dimension:
                dimension = dimension.split('=')
                name = dimension[0]
                value = dimension[1][1:-1]
                dims.append({'Name': name,'Value':value})

            value = float(line[1])
            post(dims, value)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': Exporting JVM stats\n' + str(e) + '\n')

    sleep(30)
