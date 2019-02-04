HTACCESS="c3monitoring:\$apr1\$Rc2Pbwc6\$kY8oUfd38M5jNu0fGgeeB."
sudo amazon-linux-extras install nginx1.12
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

echo $HTACCESS > /etc/nginx/.htaccess
chmod 644 /etc/nginx/.htaccess

systemctl start nginx.service
