#!/bin/bash
set -x

/sbin/service master_exporter stop
rm -rf /opt/monitoring/master_exporter /etc/init.d/master_exporter

pip=$(which pip)
if [ ! $pip ];then
  #curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  curl https://bootstrap.pypa.io/2.6/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install prometheus-client

mkdir -p /opt/monitoring/master_exporter
cd /opt/monitoring/master_exporter

touch /opt/monitoring/master_exporter/master_exporter.log

cat <<'EOF' >> /opt/monitoring/master_exporter/master_exporter
#!/usr/bin/python
# prometheus exporter for master instances
# exports login latency, old gen memory, and number of running node index.js processes

from prometheus_client import start_http_server, Gauge
from subprocess import Popen, PIPE, call
from time import sleep
from datetime import datetime

timeout = 10
url = 'https://c3iotdemo.c3-e.com/static/console/'
log_file = '/opt/monitoring/master_exporter/master_exporter.log'

if __name__ == "__main__":
  gauge = Gauge('login_stat', 'production certificates', ['login_state'])
  start_http_server(7085)

  while True:
    command = "ps -ef | grep 'node index.js' | wc -l"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    try:
      nodes = int(stdout) - 2
      gauge.labels('nodes').set(nodes)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting nodes\n' + str(e) + '\nstdout:\n' + stdout + '\nstderr:\n' + stderr + '\n\n')

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
      gauge.labels('login_latency').set(latency)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting login latency\n' + str(e) + '\nreturn_code:\n' + return_code + '\nstderr:\n' + stderr + '\n\n')

    command = '/usr/bin/tail -22222 /var/log/c3log/c3_server.log  | /bin/grep "mem_ps_old_gen=" | /usr/bin/tail -1'
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    try:
      mm = stdout.decode('utf-8').strip().split('mem_ps_old_gen=')
      old_gen = float(mm[1].replace('%,',''))
      gauge.labels('old_gen').set(old_gen)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting old gen\n' + str(e) + '\nstdout:\n' + stdout + '\nstderr:\n' + stderr + '\n\n')

    sleep(30)
EOF

chmod +x master_exporter

cat <<'EOF' >> /etc/init.d/master_exporter
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports certificate information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/master_exporter
  APP_NAME=master_exporter
  APP_PORT=7085
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
chmod +x /etc/init.d/master_exporter
/sbin/chkconfig --add master_exporter
/usr/bin/setsid /sbin/service master_exporter start &
sleep 1
