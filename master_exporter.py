#!/usr/bin/python
# prometheus exporter to report login latency, old gen memory, and number of node.js nodes
# Requirement: pip install prometheus_client
# Nick Cogswell 11/9/18

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
