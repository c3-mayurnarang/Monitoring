#!/bin/bash
set -x

/sbin/service cass_cw stop
rm -rf /opt/monitoring/cass_cw /etc/init.d/cass_cw

pip=$(which pip)
if [ ! $pip ];then
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python get-pip.py
  rm get-pip.py
fi
pip install boto3

mkdir -p /opt/monitoring/cass_cw
cd /opt/monitoring/cass_cw

touch /opt/monitoring/cass_cw/cass_cw.log

cat <<'EOF' >> /opt/monitoring/cass_cw/cass_cw
#!/usr/bin/python
# cloudwatch exporter for cassandra isntances
# exports node laod, fs usage, and select stats from jvm exporter

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
#log_file = '/opt/monitoring/cass_cw/cass_cw.log'
log_file = 'test_log'

def post(dims, value):
  dims.append({'Name':'Name','Value':name})
  '''
  client.put_metric_data(
      Namespace='MON',
      MetricData=[
          {
              'MetricName': 'cassandra',
              'Dimensions': dims,
              'Timestamp': datetime.now(),
              'Value': value,
              'Unit': 'None',
              'StorageResolution': 60
          },
      ]
  )
  '''
  print 'dims: ' + str(dims) + ' val: ' + str(value)

if __name__ == "__main__":
  while True:
    # Export node load15
    command = "cat /proc/loadavg | awk '{print $3}'"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    try:
      node_load = float(stdout)
      dims = [{'Name':'cass_state','Value':'node_load15'}]
      post(dims, node_load)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting node load\n' + str(e) + '\nstdout:\n' + str(stdout) + '\nstderr:\n' + str(stderr) + '\n\n')

    # Export file system usage
    command = "df -kT | awk '{print $1,$2,$6,$7}'"
    process = Popen(command, shell=True, stdout=PIPE, stderr=PIPE)
    stdout, stderr = process.communicate()
    return_code = process.returncode
    try:
      if return_code == 0:
        out = stdout.split('\n')
        for line in out:
          line = line.split()
          if len(line) > 3:
            f = line[0]
            t = line[1]
            p = line[2][:-1]
            m = line[3]
            #print f + ' ' + t + ' ' + p + ' ' + m
            if t in ('ext4','xfs') and p.isdigit():
              p = float(p)
              dims = [{'Name':'cass_state','Value':'fs'},{'Name':'fs','Value':f},{'Name':'mountpoint','Value':m}]
              post(dims, p)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': exporting sys stats\n' + str(e))

    # Pull and export select JVM stats
    try:
      handle = open('jvm', 'r')
      for line in handle:
        if (line.startswith('jvm_memory_bytes_used') or
            line.startswith('jvm_memory_bytes_committed') or
            line.startswith('cassandra_clientrequest_latency') or
            line.startswith('cassandra_compaction_pendingtasks')):

          line = line.split()
          if len(line) > 1:
            temp = line[0]

            if '{' in temp:
              metric = temp[:temp.find('{')]
              dimensions = temp[temp.find('{')+1:-1]
            else:
              metric = temp
              dimensions = ''

            dimensions = dimensions.split(',')
            dims = [{'Name':'metric','Value':metric},{'Name':'Host','Value':'test-host-01'}]

            for dimension in dimensions:
              if '=' in dimension:
                dimension = dimension.split('=')
                name = dimension[0]
                value = dimension[1][1:-1]
                dims.append({'Name': name,'Value':value})

            value = float(line[1])
            post(dims, value)
    except Exception as e:
      with open(log_file, "a") as log:
        log.write(str(datetime.now()) + ': Exporting JVM stats\n' + str(e) + '\n')

    sleep(30)
EOF

chmod +x cass_cw

cat <<'EOF' >> /etc/init.d/cass_cw
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Certificate Exporter
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Exports cass information to server
### END INIT INFO
  APP_PATH=/opt/monitoring/cass_cw
  APP_NAME=cass_cw
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
chmod +x /etc/init.d/cass_cw
/sbin/chkconfig --add cass_cw
/usr/bin/setsid /sbin/service cass_cw start &
sleep 1
