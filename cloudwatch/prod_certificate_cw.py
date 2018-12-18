#!/usr/bin/env python
# cloudwatch exporter for production account master
# exports all prod cert expirations and elb cert expirations for all prod envts
# install on one master node
# instance iam policy requirements: IAM read, ELB read

import os
from time import sleep
import boto3
from datetime import datetime
from subprocess import Popen, PIPE, call

client = boto3.client('cloudwatch', region_name='us-west-2')
command = "hostname"
process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
stdout, stderr = process.communicate()
name = stdout.split('.')[0]
log_file = '/opt/monitoring/prod_certificate_cw/prod_certificate_cw.log'

regions = ['us-east-1', 'us-west-2', 'eu-west-1']
pods = ['stage', 'open', 'sbox', 'prod', 'lock', 'dev']

def post_elb(elb, envt, value):
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
                      'Name': 'envt',
                      'Value': envt
                  }
              ],
              'Timestamp': datetime.now(),
              'Value': value,
              'Unit': 'None',
              'StorageResolution': 60
          },
      ]
  )

def post_cert(cert, usage, value):
  client.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': 'certificate',
              'Dimensions': [
                  {
                      'Name': 'cert',
                      'Value': cert
                  },
                  {
                      'Name': 'usage',
                      'Value': usage
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

  # Report all certificates and current certificates
  for cert in expiration:
    post_cert(cert, 'all', expiration[cert])
    if cert in used_certs:
      post_cert(cert, 'current', expiration[cert])

  # Report all load balancers
  for elb, cert, envt in elb_certs:
    psot_elb(elb, envt, expiration[cert])

  # update once a day
  sleep(86400)
