#!/bin/bash
set -x

/sbin/service zk_cw stop
rm -rf /opt/monitoring/zk_cw /etc/init.d/zk_cw

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install boto3

mkdir -p /opt/monitoring/zk_cw
cd /opt/monitoring/zk_cw

touch /opt/monitoring/zk_cw/zk_cw.log

cat <<'EOF' >> /opt/monitoring/zk_cw/zk_cw
#!/usr/bin/python
# cloudwatch exporter for zookeepers
# exports dist space and data

import os
import subprocess
from time import sleep
from datetime import datetime
from subprocess import Popen, PIPE, call
import boto3

client = boto3.client('cloudwatch', region_name='us-west-2')
command = "hostname"
process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
stdout, stderr = process.communicate()
name = stdout.split('.')[0]
log_file = '/opt/monitoring/zk_cw/zk_cw.log'
ZK_LOG_DIR = '/var/zk'
DATASOURCE = 'paas-data'

def post(zk_state, value):
  client.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': 'zookeeper',
              'Dimensions': [
                  {
                      'Name': 'zk_state',
                      'Value': zk_state
                  },
                  {
                      'Name': 'Name',
                      'Value': name
                  },
              ],
              'Timestamp': datetime.now(),
              'Value': value,
              'Unit': 'None',
              'StorageResolution': 60
          },
      ]
  )

if __name__ == "__main__":
  while True:
    disk = os.statvfs(ZK_LOG_DIR)
    percent = (disk.f_blocks - disk.f_bfree) * 100 / (disk.f_blocks - disk.f_bfree + disk.f_bavail) + 1
    post('zk_log_dir_pct',  percent)

    sss = subprocess.Popen(['/bin/echo mntr | /usr/bin/nc localhost 2181'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    r = sss.stdout.readlines()
    for i in r:
        try:
          mm = i.decode('utf-8').strip().split('\t')
          if mm[0] in ['zk_approximate_data_size', 'zk_max_latency']:
            if mm[1].isdigit():
              post(mm[0], int(mm[1]))
        except Exception as e:
          with open(log_file, "a") as log:
            log.write(str(datetime.now()) + ': ' + str(i) + '\n' + str(e) + '\n')

    sleep(30)
EOF

chmod +x zk_cw

cat <<'EOF' >> /etc/init.d/zk_cw
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports zk information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/zk_cw
  APP_NAME=zk_cw
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
chmod +x /etc/init.d/zk_cw
/sbin/chkconfig --add zk_cw
/usr/bin/setsid /sbin/service zk_cw start &
sleep 1
