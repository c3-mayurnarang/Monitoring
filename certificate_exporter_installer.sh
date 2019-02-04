#!/bin/bash
set -x

/sbin/service certificate_exporter stop
rm -rf /opt/monitoring/certificate_exporter /etc/init.d/certificate_exporter

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install prometheus-client

mkdir -p /opt/monitoring/certificate_exporter
cd /opt/monitoring/certificate_exporter

mkdir -p evar/log/certificate_exporter
touch /var/log/monitoring/certificate_exporter.log

cat <<'EOF' >> /opt/monitoring/certificate_exporter/certificate_exporter
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
EOF

chmod +x certificate_exporter

cat <<'EOF' >> /etc/init.d/certificate_exporter
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports certificate information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/certificate_exporter
  APP_NAME=certificate_exporter
  APP_PORT=7080
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

    PORT_PID=$(/usr/sbin/lsof -ti tcp:$APP_PORT)
    if [ $PORT_PID ];then
      echo process already using port $APP_PORT pid: $PORT_PID
      echo killing process $PORT_PID
      kill -9 $PORT_PID
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
      echo no process found, checking port
      PORT_PID=$(/usr/sbin/lsof -ti tcp:$APP_PORT)
      if [ $PORT_PID ];then
        echo "Stopping process using port" $APP_PORT
        kill -9 $PORT_PID
      else
        echo no process using port $APP_PORT
        echo The service is not running
      fi
    fi

  }

  status()
  {
    printf "%-50s" "Checking $APP_NAME..."
    PGREP_PID=$(pgrep -f $APP_PATH/$APP_NAME)
    if [ $PGREP_PID ];then
      printf "%s\n" "The process is running with pid: $PGREP_PID"
    else
      PORT_PID=$(/usr/sbin/lsof -ti tcp:$APP_PORT)
      if [ $PORT_PID ];then
      printf "%s\n" "A process is running on port $APP_PORT with pid: $PORT_PID"
      else
        printf "%s\n" "The service is not running"
      fi
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
chmod +x /etc/init.d/certificate_exporter
/sbin/chkconfig --add certificate_exporter
/usr/bin/setsid /sbin/service certificate_exporter start &
sleep 1
