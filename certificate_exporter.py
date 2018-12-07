from prometheus_client import start_http_server, Gauge
from time import sleep
import boto3
import os
from datetime import datetime

log_file = '/opt/monitoring/master_exporter/master_exporter.log'

start_http_server(8002)
gauge = Gauge('nypa_elb', 'some description', ['name'])
regions = ['us-east-1']
profile = 'nypa'

while True:

  now = datetime.today()

  print 'profile: ' + profile

  expiration = {}
  session = boto3.Session(profile_name=profile)

  client = session.client('sts')
  account = client.get_caller_identity()['Account']

  client = session.client('iam')
  paginator = client.get_paginator('list_server_certificates')
  for response in paginator.paginate():
    data = response['ServerCertificateMetadataList']
    for cert in data:
      expiration[cert['ServerCertificateName']] = cert['Expiration']

  for x in expiration:
    print expiration[x].strftime('%m/%d/%Y') + '\t' + x

  certs = []

  for region in regions:
    print 'region: ' + region
    session = boto3.Session(profile_name=profile, region_name=region)
    client = session.client('elb')
    elbs = client.describe_load_balancers()['LoadBalancerDescriptions']
    for elb in elbs:
      name = elb['LoadBalancerName']
      listeners = elb['ListenerDescriptions']
      for listener in listeners:
        listener = listener['Listener']
        if 'SSLCertificateId' in listener:
          cert = listener['SSLCertificateId'].split('/')[1]
          certs.append((name, cert))
    
  for elb, cert in certs:
    print name + ' ' + cert + str(expiration[cert])
    gauge.labels(elb).set((expiration[cert].replace(tzinfo=None) - now).days)

  sleep(300000)
