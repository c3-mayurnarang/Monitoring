#!/bin/bash
set -x

/sbin/service zk_exporter stop
rm -rf /opt/monitoring/zk_exporter /etc/init.d/zk_exporter

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install prometheus-client

mkdir -p /opt/monitoring/zk_exporter
cd /opt/monitoring/zk_exporter

cat <<'EOF' >> /opt/monitoring/zk_exporter/zk_exporter
#!/usr/bin/python
# prometheus exporter to report zookeeper disk
# Requirement: pip install prometheus_client
# Nick Cogswell 11/9/18

import os
import subprocess
from time import sleep
from prometheus_client import start_http_server, Gauge

ZK_LOG_DIR = '/var/zk'
DATASOURCE = 'paas-data'

if __name__ == "__main__":
  gauge = Gauge('zookeeper_states', 'The current state of Zookeeper', ['zk_state', 'keyspace'])
  start_http_server(7071)

  while True:
    disk = os.statvfs(ZK_LOG_DIR)
    percent = (disk.f_blocks - disk.f_bfree) * 100 / (disk.f_blocks - disk.f_bfree + disk.f_bavail) + 1
    avail = (disk.f_blocks - disk.f_bfree) * disk.f_bsize

    gauge.labels('zk_log_dir_pct', DATASOURCE).set(percent)
    gauge.labels('zk_log_dir_avail', DATASOURCE).set(avail)

    sss = subprocess.Popen(['/bin/echo mntr | /usr/bin/nc localhost 2181'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    r = sss.stdout.readlines()
    for i in r:
        mm = i.decode('utf-8').strip().split('\t')
        if mm[1].isdigit():
          gauge.labels(mm[0], DATASOURCE).set(int(mm[1]))
    '''
      if 'zk_approximate_data_size' in i:
        mm = i.decode('utf-8').strip().split('\t')
        gauge.labels('zk_data_size', DATASOURCE).set(int(mm[1]))
      elif 'zk_max_latency' in i:
        mm = i.decode('utf-8').strip().split('\t')
        gauge.labels('zk_max_latency', DATASOURCE).set(int(mm[1]))
    '''
    sleep(30)
EOF

chmod +x zk_exporter

cat <<'EOF' >> /etc/init.d/zk_exporter
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports certificate information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/zk_exporter
  APP_NAME=zk_exporter
  APP_PORT=7071
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
chmod +x /etc/init.d/zk_exporter
/sbin/chkconfig --add zk_exporter
/usr/bin/setsid /sbin/service zk_exporter start &
sleep 1
