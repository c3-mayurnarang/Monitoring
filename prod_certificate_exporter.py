#!/usr/bin/env python
# certificate exporter for production account
# install on one master node

from prometheus_client import start_http_server, Gauge
from time import sleep
import boto3
from datetime import datetime

log_file = '/opt/monitoring/master_exporter/master_exporter.log'
start_http_server(7080)
elb_gauge = Gauge('elb', 'Reports the certificate expiration for each elb in production account', ['name', 'envt'])
certificate_gauge = Gauge('certificates', 'Reports expiration for each certification in production account', ['name', 'usage'])

regions = ['us-east-1', 'us-west-2', 'eu-west-1']
pods = ['stage', 'open', 'sbox', 'prod', 'lock', 'dev']

while True:
  now = datetime.today()

  # Get all certificates
  expiration = {}
  client = boto3.client('iam')
  paginator = client.get_paginator('list_server_certificates')
  for response in paginator.paginate():
    data = response['ServerCertificateMetadataList']
    for cert in data:
      expiration[cert['ServerCertificateName']] = (cert['Expiration'].replace(tzinfo=None) - now).days

  # Get all certificates pointed to by an elb
  used_certs = []
  elb_certs = []
  for region in regions:
    session = boto3.Session(region_name=region)
    client = session.client('elb')
    elbs = client.describe_load_balancers()['LoadBalancerDescriptions']
    for elb in elbs:
      name = elb['LoadBalancerName']
      listeners = elb['ListenerDescriptions']
      for listener in listeners:
        listener = listener['Listener']
        if 'SSLCertificateId' in listener:
          cert = listener['SSLCertificateId'].split('/')[1]
          envt = ''
          try:
            parts = name.split('-')
            if parts[0] in pods:
              envt = parts[0] + ' ' + parts[1]
            else:
              envt = 'other'
          except:
            envt = 'other'

          elb_certs.append((name, cert, envt))
          if cert not in used_certs:
            used_certs.append(cert)

  # Report all certificates
  for cert in expiration:
    certificate_gauge.labels(cert, 'all').set(expiration[cert])

  # Report all currently used certificates
  for cert in expiration:
    if cert in used_certs:
      certificate_gauge.labels(cert, 'current').set(expiration[cert])

  # Report all load balancers
  for elb, cert, envt in elb_certs:
    elb_gauge.labels(elb, envt).set(expiration[cert])

  # update once a day
  sleep(86400)
