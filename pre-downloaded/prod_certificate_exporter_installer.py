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

touch /opt/monitoring/certificate_exporter/certificate_exporter.log

cat <<'EOF' >> /opt/monitoring/certificate_exporter/certificate_exporter
#!/usr/bin/env python
# prometheus exporter for production account master
# exports all prod cert expirations and elb cert expirations for all prod envts
# install on one master node
# instance iam policy requirements: IAM read, ELB read

from prometheus_client import start_http_server, Gauge
from time import sleep
import boto3
from datetime import datetime

log_file = '/opt/monitoring/prod_certificate_exporter/prod_certificate_exporter.log'
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
