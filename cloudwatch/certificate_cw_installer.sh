#!/bin/bash
set -x

/sbin/service certificate_cw stop
rm -rf /opt/monitoring/certificate_cw /etc/init.d/certificate_cw

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install boto3

mkdir -p /opt/monitoring/certificate_cw
cd /opt/monitoring/certificate_cw

touch /opt/monitoring/certificate_cw/certificate_cw.log

cat <<'EOF' >> /opt/monitoring/certificate_cw/certificate_cw
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
EOF

chmod +x certificate_cw

cat <<'EOF' >> /etc/init.d/certificate_cw
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports certificate information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/certificate_cw
  APP_NAME=certificate_cw
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
chmod +x /etc/init.d/certificate_cw
/sbin/chkconfig --add certificate_cw
/usr/bin/setsid /sbin/service certificate_cw start &
sleep 1
