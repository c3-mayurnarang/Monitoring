#!/bin/bash
set -x

# MANDATORY VARIABLE:
CUST_NAME="aep"
ENV_NAME="prod"
ENV_REGION="us-east-1"
# END MANDATORY VARIABLE
# START SCRIPT
PROMETHEUS_FILE=/opt/monitoring/prometheus/current/prometheus.yml
TMP_CRED_FILE=/tmp/derc_tmp
AWS_S3_BUCKET=c3--exp-test-monitoring-locker-850572970568/credentials
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
hostname exp-test-mon-01.something.internal
if vgs | grep -q 'dataMonitoring'; then
  echo "nothing to do"
else
  echo "creating pv, vg and lv for dedicated FS to prometheus"
  pvcreate /dev/sdb
  vgcreate dataMonitoring /dev/sdb
  lvcreate --name prometheus --extents 100%FREE dataMonitoring
  yum install xfsprogs -y
  mkfs.xfs /dev/mapper/dataMonitoring-prometheus
  mkdir /opt/monitoring
  echo '/dev/mapper/dataMonitoring-prometheus  /opt/monitoring xfs defaults 0  2' >> /etc/fstab
  mount /dev/mapper/dataMonitoring-prometheus /opt/monitoring
  echo "download and install prometheus"
  mkdir /opt/monitoring/prometheus
  cd /opt/monitoring/prometheus
  curl -L 'https://github.com/prometheus/prometheus/releases/download/v1.8.1/prometheus-1.8.1.linux-amd64.tar.gz' -o prometheus-1.8.1.linux-amd64.tar.gz
  tar -zxvf prometheus-1.8.1.linux-amd64.tar.gz
  ln -s /opt/monitoring/prometheus/prometheus-1.8.1.linux-amd64 /opt/monitoring/prometheus/current
  mkdir /var/log/prometheus /var/run/prometheus
  cat <<'EOF' >> /etc/init.d/prometheus
  #!/bin/sh
  ### BEGIN INIT INFO
  # Provides:          Prometheus server
  # Required-Start:    $local_fs $network $named $time $syslog
  # Required-Stop:     $local_fs $network $named $time $syslog
  # Default-Start:     2 3 4 5
  # Default-Stop:      0 1 6
  # Description:       Custom Prometheus init script
  ### END INIT INFO

  APP_PATH=/opt/monitoring/prometheus/current/
  APP_NAME=prometheus
  APP_PORT=9090
  CONF_FILE=${APP_PATH}prometheus.yml
  USER=root
  PIDFILE=/var/run/$APP_NAME/${APP_NAME}.pid
  LOGFILE=/var/log/$APP_NAME/${APP_NAME}.log
  ARGS=""
  [ -r /etc/default/${APP_NAME} ] && . /etc/default/${APP_NAME}

  do_start_cmd()
  {
      if [[ -e $PIDFILE ]];then
        PIDNUM=$(cat $PIDFILE)
        PIDNUMVAL=$(echo $PIDNUM | grep '\d*')
        if [[ $PIDNUMVAL ]]; then
          if ps -p $PIDNUM --no-header; then
            printf "%s\n" "The process is already running with PID : $PIDNUM"
          else
            rm -rf $PIDFILE
            do_start_cmd
          fi
        else
          PRPORTEST=$(/usr/sbin/lsof -ti tcp:$APP_PORT || echo '')
          if [[ $PRPORTEST ]]; then
            printf "%s\n" "The process is already running with PID : ${PRPORTEST}"
            echo $PRPORTEST > $PIDFILE
          else
            rm -rf $PIDFILE
            do_start_cmd
          fi
        fi
      else
        if [[ -e $APP_PATH$APP_NAME ]];then
          PRPORTEST=$(/usr/sbin/lsof -ti tcp:$APP_PORT || echo '')
          if [[ $PRPORTEST ]]; then
            printf "%s\n" "The process is already started with PID : $PIDNUM"
            echo $PRPORTEST > $PIDFILE
          else
            printf "%s\n" "Starting daemon: $APP_NAME"
            /usr/bin/setsid $APP_PATH$APP_NAME -config.file=$CONF_FILE -storage.local.path=/opt/monitoring/prometheus/data&
            sleep 5
            # Give time to prometheus to start to identify the PID for the next command
            /usr/sbin/lsof -ti tcp:$APP_PORT > $PIDFILE
          fi
        else
          printf "%s\n" "the binary $APP_PATH$APP_NAME is not installed"
        fi
      fi
  }
  do_stop_cmd()
  {
      if [ -f $PIDFILE ]; then
        printf "%s\n" "Stopping daemon: $APP_NAME"
        kill -9 $(cat $PIDFILE)
        rm -rf $PIDFILE
      fi
  }
  status() {
      printf "%-50s" "Checking ${APP_NAME}..."
      if [ -f $PIDFILE ]; then
        PIDNUM=$(cat $PIDFILE)
        PIDNUMVAL=$(echo $PIDNUM | grep '\d*')
        if [[ $PIDNUMVAL ]]; then
          if ps -p $PIDNUM --no-header; then
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
  chmod +x /etc/init.d/prometheus
  chkconfig --add prometheus
  mv /opt/monitoring/prometheus/current/prometheus.yml /opt/monitoring/prometheus/current/prometheus.yml.ORG
  touch /opt/monitoring/prometheus/current/prometheus.yml
  cat <<EOF >> /opt/monitoring/prometheus/current/prometheus.yml
global:
    scrape_interval:     15s 
    evaluation_interval: 15s 
    external_labels:
      monitor: 'codelab-monitor'

rule_files:
  - "rules/*.rules"

scrape_configs:
  - job_name: '$ENV_NAME-$CUST_NAME-prometheus'
    static_configs:
    - targets: ['localhost:9100']
      labels:
        env: $ENV_NAME
        customer:  $CUST_NAME
        region: $ENV_REGION
        instance: $ENV_NAME-$CUST_NAME-mon-01
  - job_name: '$ENV_NAME-$CUST_NAME'
    ec2_sd_configs:
      - region: $ENV_REGION
        access_key: {{AWS_CRED_ID}}
        secret_key: {{AWS_CRED_KEY}}
        port: 9100
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Name]
        regex: $ENV_NAME-$CUST_NAME-.*
        action: keep
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance
      - replacement: $ENV_NAME
        target_label: env
      - replacement: $CUST_NAME
        target_label: customer
      - replacement: $ENV_REGION
        target_label: region
EOF

  /etc/init.d/prometheus status
  yum install -y nginx.x86_64
  mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.org
  touch /etc/nginx/nginx.conf
  cat <<'EOF' >> /etc/nginx/nginx.conf
  # For more information on configuration, see:
  #   * Official English Documentation: http://nginx.org/en/docs/
  #   * Official Russian Documentation: http://nginx.org/ru/docs/
  user nginx;
  worker_processes auto;
  error_log /var/log/nginx/error.log;
  pid /var/run/nginx.pid;
  include /usr/share/nginx/modules/*.conf;
  events {
      worker_connections 1024;
  }
  http {
      log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';
      access_log  /var/log/nginx/access.log  main;
      sendfile            on;
      tcp_nopush          on;
      tcp_nodelay         on;
      keepalive_timeout   65;
      types_hash_max_size 2048;
      include             /etc/nginx/mime.types;
      default_type        application/octet-stream;
      server {
        listen 0.0.0.0:80;
        location / {
          proxy_pass http://localhost:9090/;
          auth_basic "Authentification required";
          auth_basic_user_file "/etc/nginx/.htaccess";
        }
      }
  }
EOF
  
  echo "retrieving credentials from bucket"
  aws s3 cp --quiet s3://$AWS_S3_BUCKET/c3monitoring $TMP_CRED_FILE

  if [ $? -eq 0 ] && [ -f $TMP_CRED_FILE ]; then
    declare -A arrCredential
    while read line; do
      C3_CRED_ID=$(echo $line | awk -F ',' '{ print $1 }')
      C3_CRED_KEY=$(echo $line | awk -F ',' '{ print $2 }')
      arrCredential=([id]=$C3_CRED_ID [key]=$C3_CRED_KEY)
    done < $TMP_CRED_FILE
  
    sed -i 's/{{AWS_CRED_ID}}/'${arrCredential['id']}'/' $PROMETHEUS_FILE
    sed -i 's/{{AWS_CRED_KEY}}/'${arrCredential['key']}'/' $PROMETHEUS_FILE
    rm -rf $TMP_CRED_FILE
  else
    rm -rf $TMP_CRED_FILE
    echo "A problem attempted when retrieving the file"
  fi
  aws s3 cp --quiet s3://$AWS_S3_BUCKET/htaccess.txt /etc/nginx/.htaccess
  chmod 644 /etc/nginx/.htaccess
  service prometheus start
  chkconfig --add nginx
  chkconfig nginx on
  service nginx start
  echo "Start installing node_exporter"
  mkdir /opt/monitoring/node_exporter
  cd /opt/monitoring/node_exporter
  curl -L 'https://github.com/prometheus/node_exporter/releases/download/v0.15.0/node_exporter-0.15.0.linux-amd64.tar.gz' -o node_exporter-0.15.0.linux-amd64.tar.gz
  tar -zxvf node_exporter-0.15.0.linux-amd64.tar.gz
  ln -s /opt/monitoring/node_exporter/node_exporter-0.15.0.linux-amd64 /opt/monitoring/node_exporter/current
  mkdir /var/log/node_exporter /var/run/node_exporter
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
  PARAM=" --no-collector.arp --no-collector.bcache --no-collector.conntrack --no-collector.edac --no-collector.entropy --no-collector.filefd --no-collector.hwmon --no-collector.infiniband --no-collector.ipvs --no-collector.mdadm --no-collector.wifi --no-collector.zfs"
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
  chkconfig --add node_exporter
  service node_exporter start
  echo "Start installing Alert manager"
  mkdir /opt/monitoring/alertmanager
  cd /opt/monitoring/alertmanager
  curl -L 'https://github.com/prometheus/alertmanager/releases/download/v0.9.1/alertmanager-0.9.1.linux-amd64.tar.gz' -o alertmanager-0.9.1.linux-amd64.tar.gz
  tar -zxvf alertmanager-0.9.1.linux-amd64.tar.gz
  ln -s /opt/monitoring/alertmanager/alertmanager-0.9.1.linux-amd64 /opt/monitoring/alertmanager/current
  mkdir /var/log/alertmanager /var/run/alertmanager
  touch /etc/init.d/alert_manager
  cat <<'EOF' >> /etc/init.d/alert_manager
  #!/bin/sh
  ### BEGIN INIT INFO
  # Provides:          Alertmanager
  # Required-Start:    $local_fs $network $named $time $syslog
  # Required-Stop:     $local_fs $network $named $time $syslog
  # Default-Start:     2 3 4 5
  # Default-Stop:      0 1 6
  # Description:       Custom Prometheus init script
  ### END INIT INFO

  APP_PATH=/opt/monitoring/alertmanager/current/
  APP_NAME=alertmanager
  CONF_FILE=${APP_PATH}alertmanager.yml
  APP_PORT=9093
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
            /usr/bin/setsid $APP_PATH/$APP_NAME &
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
  chmod +x /etc/init.d/alert_manager
  chkconfig --add alert_manager
fi

