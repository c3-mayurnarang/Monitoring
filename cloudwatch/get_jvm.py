from datetime import datetime
import boto3

client = boto3.client('cloudwatch', region_name='us-west-2')
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
      client.put_metric_data(
        Namespace='JVM',
        MetricData=[
          {
            'MetricName': 'jvm',
            'Dimensions': dims,
            'Timestamp': datetime.now(),
            'Value': value,
            'Unit': 'None',
            'StorageResolution': 60
          },
        ]
      )
