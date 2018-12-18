#!/usr/bin/python
# cloudwatch exporter for individual account master instance
# exports certificate expiration for all elbs
# instance iam policy requirements: IAM read, ELB read

from time import sleep
from subprocess import Popen, PIPE, call
import boto3
import os
from datetime import datetime

client = boto3.client('cloudwatch', region_name='us-west-2')
command = "hostname"
process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
stdout, stderr = process.communicate()
name = stdout.split('.')[0]
log_file = '/opt/monitoring/certificate_cw/certificate_cw.log'
regions = ['us-east-1', 'us-west-1']

def post(elb, value):
  client.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': 'elb',
              'Dimensions': [
                  {
                      'Name': 'elb',
                      'Value': elb
                  },
                  {
                      'Name': 'Name',
                      'Value': name
                  }
              ],
              'Timestamp': datetime.now(),
              'Value': value,
              'Unit': 'None',
              'StorageResolution': 60
          },
      ]
  )

while True:

  now = datetime.today()
  expiration = {}

  try:
    client = boto3.client('iam')
    paginator = client.get_paginator('list_server_certificates')
    for response in paginator.paginate():
      data = response['ServerCertificateMetadataList']
      for cert in data:
        expiration[cert['ServerCertificateName']] = cert['Expiration']
  except Exception as e:
    with open(log_file, "a") as log:
      log.write(str(datetime.now()) + ': getting cert expirations\n' + str(e) + '\n')

  certs = []

  try:
    for region in regions:
      client = boto3.client('elb', region_name=region)
      elbs = client.describe_load_balancers()['LoadBalancerDescriptions']
      for elb in elbs:
        name = elb['LoadBalancerName']
        listeners = elb['ListenerDescriptions']
        for listener in listeners:
          listener = listener['Listener']
          if 'SSLCertificateId' in listener:
            cert = listener['SSLCertificateId'].split('/')[1]
            certs.append((name, cert))
  except Exception as e:
    with open(log_file, "a") as log:
      log.write(str(datetime.now()) + ': getting elb cert\n' + str(e) + '\n')
    
  try:
    for elb, cert in certs:
      post(elb, (expiration[cert].replace(tzinfo=None) - now).days)
  except Exception as e:
    with open(log_file, "a") as log:
      log.write(str(datetime.now()) + ': setting gauge value\n' + str(e) + '\n')

  sleep(86400)
