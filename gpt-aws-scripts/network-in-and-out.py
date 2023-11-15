import boto3
import csv
from datetime import datetime, timedelta

ec2 = boto3.resource('ec2')
cloudwatch = boto3.client('cloudwatch')

three_days_ago = datetime.utcnow() - timedelta(days=3)
start_time = three_days_ago.strftime('%Y-%m-%dT%H:%M:%SZ')
end_time = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

instance_stats = []

instances = ec2.instances.all()

for instance in instances:
    if instance.state['Name'] == 'running':
        instance_id = instance.id
        instance_type = instance.instance_type
        instance_launch_time = instance.launch_time
        instance_spot_or_od = 'spot' if instance.instance_lifecycle == 'spot' else 'on-demand'
        
        network_stats = cloudwatch.get_metric_data(
            MetricDataQueries=[
                {
                    'Id': 'network_in',
                    'MetricStat': {
                        'Metric': {
                            'Namespace': 'AWS/EC2',
                            'MetricName': 'NetworkIn',
                            'Dimensions': [
                                {
                                    'Name': 'InstanceId',
                                    'Value': instance_id
                                },
                            ]
                        },
                        'Period': 86400,
                        'Stat': 'Sum',
                        'Unit': 'Bytes'
                    },
                    'ReturnData': True
                },
                {
                    'Id': 'network_out',
                    'MetricStat': {
                        'Metric': {
                            'Namespace': 'AWS/EC2',
                            'MetricName': 'NetworkOut',
                            'Dimensions': [
                                {
                                    'Name': 'InstanceId',
                                    'Value': instance_id
                                },
                            ]
                        },
                        'Period': 86400,
                        'Stat': 'Sum',
                        'Unit': 'Bytes'
                    },
                    'ReturnData': True
                },
            ],
            StartTime=start_time,
            EndTime=end_time
        )

        for result in network_stats['MetricDataResults']:
            if result['Id'] == 'network_in':
                network_in = result['Values'][0] / 1024 / 1024 / 1024  # convert to GB
            elif result['Id'] == 'network_out':
                network_out = result['Values'][0] / 1024 / 1024 / 1024  # convert to GB

        instance_stats.append([instance_id, instance_type, instance_launch_time, instance_spot_or_od, network_in, network_out])

with open('network_stats.csv', mode='w', newline='') as file:
    writer = csv.writer(file)
    writer.writerow(['Instance ID', 'Instance Type', 'Launch Time', 'Spot/On-Demand', 'Network In (GB)', 'Network Out (GB)'])
    writer.writerows(instance_stats)

