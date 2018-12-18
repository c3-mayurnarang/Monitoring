#!/bin/bash
set -x

/sbin/service master_cw stop
rm -rf /opt/monitoring/master_cw /etc/init.d/master_cw

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install boto3

mkdir -p /opt/monitoring/master_cw
cd /opt/monitoring/master_cw

touch /opt/monitoring/master_cw/master_cw.log

cat <<'EOF' >> /opt/monitoring/master_cw/master_cw
#!/usr/bin/python
# prometheus exporter for master instances
# exports login latency, old gen memory, and number of running node index.js processes

import os
from subprocess import Popen, PIPE, call
from time import sleep
from datetime import datetime
import boto3

client = boto3.client('cloudwatch', region_name='us-west-2')
command = "hostname"
process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
stdout, stderr = process.communicate()
name = stdout.split('.')[0]
timeout = 10
url = 'https://c3iotdemo.c3-e.com/static/console/'
log_file = '/opt/monitoring/master_cw/master_cw.log'

def post(ls, value):
  client.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': 'master',
              'Dimensions': [
                  {
                      'Name': 'login_state',
                      'Value': ls
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

if __name__ == "__main__":
  while True:
    command = "ps -ef | grep 'node index.js' | wc -l"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    try:
      nodes = int(stdout) - 2
      post('nodes', nodes)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting nodes\n' + str(e) + '\nstdout:\n' + str(stdout) + '\nstderr:\n' + str(stderr) + '\n\n')

    command = "time /usr/bin/curl " + url + " -u C3SecOff:SecOff@c3iot -m " + str(timeout) + " 2>&1 | grep 'title=\"C3 IoT Console\"'"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    return_code = process.returncode

    try:
      latency = timeout
      if return_code == 0:
        stderr = stderr.split('\n')
        realtime = stderr[1].split('\t')
        latency = float(realtime[1][2:-1])
      post('login_latency', latency)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting login latency\n' + str(e) + '\nreturn_code:\n' + str(return_code) + '\nstderr:\n' + str(stderr) + '\n\n')

    command = '/usr/bin/tail -22222 /var/log/c3log/c3_server.log  | /bin/grep "mem_ps_old_gen=" | /usr/bin/tail -1'
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    try:
      mm = stdout.decode('utf-8').strip().split('mem_ps_old_gen=')
      old_gen = float(mm[1].replace('%,',''))
      post('old_gen', old_gen)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting old gen\n' + str(e) + '\nstdout:\n' + str(stdout) + '\nstderr:\n' + str(stderr) + '\n\n')

    command = "cat /proc/loadavg | awk '{print $3}'"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    try:
      node_load = float(stdout)
      post('node_load15', node_load)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting node load\n' + str(e) + '\nstdout:\n' + str(stdout) + '\nstderr:\n' + str(stderr) + '\n\n')

    sleep(30)
EOF

chmod +x master_cw

cat <<'EOF' >> /etc/init.d/master_cw
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports master information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/master_cw
  APP_NAME=master_cw
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
chmod +x /etc/init.d/master_cw
/sbin/chkconfig --add master_cw
/usr/bin/setsid /sbin/service master_cw start &
sleep 1
