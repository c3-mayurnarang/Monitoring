#!/bin/bash
set -x

/sbin/service test_cw stop
rm -rf /opt/monitoring/test_cw /etc/init.d/test_cw

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install boto3

mkdir -p /opt/monitoring/test_cw
cd /opt/monitoring/test_cw

touch /opt/monitoring/test_cw/test_cw.log

cat <<'EOF' >> /opt/monitoring/test_cw/test_cw
#!/usr/bin/python
from time import sleep
import boto3
import os
from datetime import datetime
from subprocess import Popen, PIPE, call

CLIENT = boto3.client('cloudwatch', region_name='us-west-2')
log_file = '/opt/monitoring/test_exporter/test_exporter.log'
regions = ['us-east-1']

def post(elb, value):
  CLIENT.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': metric,
              'Dimensions': [
                  {
                      'Name': 'elb',
                      'Value': elb
                  },
              ],
              'Timestamp': datetime.now(),
              'Value': value,
              'Unit': 'Days',
              'StorageResolution': 60
          },
      ]
  )

while True:

  command = "df | awk '{print $1,$2}'"
  process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
  stdout, stderr = process.communicate()
  return_code = process.returncode

  if return_code == 0:
    stdout = stdout.split('\n')
    for line in stdout:
      a,b = line.split()
      if b.isdigit():
        print a + ': ' + b
        try:
          post(a, b)
        except Exception as e:
          with open(log_file, "a") as log:
            log.write(str(datetime.now()) + ' ' + str(e) + '\nreturn_code:\n' + return_code + '\nstderr:\n' + stderr + '\n\n')

  sleep(86400)
EOF

chmod +x test_cw

cat <<'EOF' >> /etc/init.d/test_cw
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports test information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/test_cw
  APP_NAME=test_cw
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
chmod +x /etc/init.d/test_cw
/sbin/chkconfig --add test_cw
/usr/bin/setsid /sbin/service test_cw start &
sleep 1
