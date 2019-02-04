#!/bin/bash
set -x

sudo /sbin/service node_exporter stop
rm -rf /etc/init.d/node_exporter
mkdir -p /opt/monitoring/node_exporter
cd /opt/monitoring/node_exporter
ln -s /opt/monitoring/node_exporter/node_exporter-0.15.0.linux-amd64 /opt/monitoring/node_exporter/current
mkdir /var/log/node_exporter
mkdir /var/run/node_exporter
cat <<'EOF' >> /etc/init.d/node_exporter
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Prometheus server
# Required-Start:    $local_fs $network $named $time $syslog
# Required-Stop:     $local_fs $network $named $time $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Custom Prometheus init script
### END INIT INFO
  APP_PATH=/opt/monitoring/node_exporter/current/
  APP_NAME=node_exporter 
  PARAM="--no-collector.arp --no-collector.bcache --no-collector.conntrack --no-collector.edac --no-collector.entropy --no-collector.filefd --no-collector.hwmon --no-collector.infiniband --no-collector.ipvs --no-collector.mdadm --no-collector.wifi --no-collector.zfs"
  APP_PORT=9100
  USER=root
  PIDFILE=/var/run/$APP_NAME/$APP_NAME.pid
  LOGFILE=/var/log/$APP_NAME/$APP_NAME.log
  ARGS=""
  [ -r /etc/default/$APP_NAME ] && . /etc/default/$APP_NAME

  do_start_cmd()
  {
      if [[ -e $PIDFILE ]];then
        PIDNUM=$(cat $PIDFILE)
        PIDNUMVAL=$(echo $PIDNUM | grep '\d*')
        if [[ $PIDNUMVAL ]]; then
          if [[ $(ps -p $PIDNUM --no-header) ]]; then
            echo "The process is already running with PID : $PIDNUM"
          else
            rm -rf $PIDFILE
            do_start_cmd
          fi
        else
          PRPORTEST=$(/usr/sbin/lsof -ti tcp:$APP_PORT || echo '')
          if [[ $PRPORTEST ]]; then
            echo "The process is already running with PID : $PRPORTEST"
            echo $PRPORTEST > $PIDFILE
          else
            rm -rf $PIDFILE
            do_start_cmd
          fi
        fi
      else
        if [[ -e $APP_PATH/$APP_NAME ]];then
          PRPORTEST=$(/usr/sbin/lsof -ti tcp:$APP_PORT || echo '')
          if [[ $PRPORTEST ]]; then
            echo "The process is already running with PID : $PIDNUM"
            echo $PRPORTEST > $PIDFILE
          else
            echo -n "Starting daemon: " $APP_NAME
            /usr/bin/setsid $APP_PATH/$APP_NAME $PARAM &
            sleep 5
            # Give time to prometheus to start to identify the PID for the next command
            /usr/sbin/lsof -ti tcp:$APP_PORT > $PIDFILE
          fi
        else
          echo "the binary $APP_PATH/$APP_NAME is not installed"
        fi
      fi
  }

  do_stop_cmd()
  {
    if [ -f $PIDFILE ]; then
      echo -n "Stopping daemon: " $APP_NAME
      kill -9 $(cat $PIDFILE)
      rm $PIDFILE
      echo "."
    fi
  }

  status() {
      printf "%-50s" "Checking $APP_NAME..."
      if [ -f $PIDFILE ]; then
        PIDNUM=$(cat $PIDFILE)
        PIDNUMVAL=$(echo $PIDNUM | grep '\d*')
        if [[ $PIDNUMVAL ]]; then
          if [[ $(ps -p $PIDNUM --no-header) ]]; then
            printf "%s\n" "The process is running with PID : $PIDNUM"
          else
            rm -rf $PIDFILE
            printf "%s\n" "The service is not running"
          fi
        else
          PRPORTEST=$(/usr/sbin/lsof -ti tcp:$APP_PORT || echo '')
          if [[ $PRPORTEST ]]; then
            printf "%s\n" "The process is already running with PID : $PRPORTEST"
            echo $PRPORTEST > $PIDFILE
          else
            printf "%s\n" "The service is not running"
          fi
        fi
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
chmod +x /etc/init.d/node_exporter
sudo /sbin/chkconfig --add node_exporter
sudo /usr/bin/setsid /sbin/service node_exporter start &
sleep 1
