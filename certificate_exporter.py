#!/usr/bin/python
# prometheus exporter for individual account master instance
# exports certificate expiration for all elbs
# instance iam policy requirements: IAM read, ELB read

from prometheus_client import start_http_server, Gauge
from time import sleep
import boto3
import os
from datetime import datetime

log_file = '/var/log/certificate_exporter/certificate_exporter.log'

start_http_server(7080)
gauge = Gauge('elb', 'Certificate expiration for each load balancer', ['name','cert'])
regions = ['us-east-1']

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
      gauge.labels(elb, cert).set((expiration[cert].replace(tzinfo=None) - now).days)
  except Exception as e:
    with open(log_file, "a") as log:
      log.write(str(datetime.now()) + ': setting gauge value\n' + str(e) + '\n')

  sleep(86400)
