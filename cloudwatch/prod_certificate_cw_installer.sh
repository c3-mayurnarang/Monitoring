#!/bin/bash
set -x

/sbin/service prod_certificate_cw stop
rm -rf /opt/monitoring/prod_certificate_cw /etc/init.d/prod_certificate_cw

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install boto3

mkdir -p /opt/monitoring/prod_certificate_cw
cd /opt/monitoring/prod_certificate_cw

touch /opt/monitoring/prod_certificate_cw/prod_certificate_cw.log

cat <<'EOF' >> /opt/monitoring/prod_certificate_cw/prod_certificate_cw
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
EOF

chmod +x prod_certificate_cw

cat <<'EOF' >> /etc/init.d/prod_certificate_cw
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports prod_certificate information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/prod_certificate_cw
  APP_NAME=prod_certificate_cw
  USER=root
  ARGS=""
  [ -r /etc/default/$APP_NAME ] && . /etc/default/$APP_NAME

  do_start_cmd()
  {
    PGREP_PID=$(pgrep -f $APP_PATH/$APP_NAME)
    if [ $PGREP_PID ];then
      echo process already running with pid: $PGREP_PID
      echo killing process $PGREP_PID
      kill -9 $PGREP_PID
    fi

    if [[ -e $APP_PATH/$APP_NAME ]];then
      echo "Starting daemon: " $APP_NAME
      /usr/bin/setsid $APP_PATH/$APP_NAME $PARAM &
    else
      echo "the binary $APP_PATH/$APP_NAME is not installed"
    fi
  }

  do_stop_cmd()
  {
    PGREP_PID=$(pgrep -f $APP_PATH/$APP_NAME)
    if [ $PGREP_PID ];then
      echo "Stopping daemon: " $APP_NAME
      kill -9 $PGREP_PID
    else
      echo The service is not running
    fi

  }

  status()
  {
    printf "%-50s" "Checking $APP_NAME..."
    PGREP_PID=$(pgrep -f $APP_PATH/$APP_NAME)
    if [ $PGREP_PID ];then
      printf "%s\n" "The process is running with pid: $PGREP_PID"
    else
      printf "%s\n" "The service is not running"
    fi
  }

  case "$1" in
    start)
      do_start_cmd
      ;;
    stop)
      do_stop_cmd
      ;;
    status)
      status
      ;;
    restart)
      do_stop_cmd
      do_start_cmd
      ;;
    *)
      echo "Usage: $1 {start|stop|status|restart}"
      exit 1
  esac
  exit 0
EOF
chmod +x /etc/init.d/prod_certificate_cw
/sbin/chkconfig --add prod_certificate_cw
/usr/bin/setsid /sbin/service prod_certificate_cw start &
sleep 1
