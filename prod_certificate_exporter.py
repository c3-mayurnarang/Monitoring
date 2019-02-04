#!/usr/bin/env python
# prometheus exporter for production account master
# exports all prod cert expirations and elb cert expirations for all prod envts
# install on one master node
# instance iam policy requirements: IAM read, ELB read

from prometheus_client import start_http_server, Gauge
from time import sleep
import boto3
from datetime import datetime

log_file = '/var/log/prod_certificate_exporter/prod_certificate_exporter.log'
start_http_server(7080)
elb_gauge = Gauge('elb', 'Reports the certificate expiration for each elb in production account', ['name', 'cert', 'envt'])
certificate_gauge = Gauge('certificates', 'Reports expiration for each certification in production account', ['name', 'usage'])

regions = ['us-east-1', 'us-west-2', 'eu-west-1']
pods = ['stage', 'open', 'sbox', 'prod', 'lock', 'dev']

while True:
  now = datetime.today()

  # Get all certificates
  expiration = {}
  try:
    client = boto3.client('iam')
    paginator = client.get_paginator('list_server_certificates')
    for response in paginator.paginate():
      data = response['ServerCertificateMetadataList']
      for cert in data:
        expiration[cert['ServerCertificateName']] = (cert['Expiration'].replace(tzinfo=None) - now).days
  except Exception as e:
    with open(log_file, "a") as log:
      log.write(str(datetime.now()) + ': getting all certs\n' + str(e) + '\n')

  # Get all certificates pointed to by an elb
  used_certs = []
  elb_certs = []
  try:
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
  except Exception as e:
    with open(log_file, "a") as log:
      log.write(str(datetime.now()) + ': getting all elb certs\n' + str(e) + '\n')

  # Report all certificates
  for cert in expiration:
    certificate_gauge.labels(cert, 'all').set(expiration[cert])

  # Report all currently used certificates
  for cert in expiration:
    if cert in used_certs:
      certificate_gauge.labels(cert, 'current').set(expiration[cert])

  # Report all load balancers
  for elb, cert, envt in elb_certs:
    elb_gauge.labels(elb, cert, envt).set(expiration[cert])

  # update once a day
  sleep(86400)
