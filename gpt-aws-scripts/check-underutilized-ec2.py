import boto3
import csv
from datetime import datetime, timedelta

# Initialize the clients
ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')

# Get all the EC2 instances
reservations = ec2.describe_instances()

# Create a CSV file to write the instance data and monitoring metrics
with open('instance_metrics.csv', mode='w', newline='') as csv_file:
    writer = csv.writer(csv_file)
    # Write the header row
    writer.writerow(['Instance ID', 'Instance Type', 'State', 'Launch Time', 'Lifecycle', 'CPU Utilization', 'Memory Utilization'])

    for reservation in reservations['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            instance_type = instance['InstanceType']
            state = instance['State']['Name']
            launch_time = instance['LaunchTime'].strftime('%Y-%m-%d %H:%M:%S')
            lifecycle = instance['InstanceLifecycle'] if 'InstanceLifecycle' in instance else 'On-demand'

            # Get the CPU utilization for the past 24 hours
            cpu_metric = cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                StartTime=(datetime.utcnow() - timedelta(days=1)).replace(hour=0, minute=0, second=0),
                EndTime=datetime.utcnow().replace(hour=0, minute=0, second=0),
                Period=86400,
                Statistics=['Average']
            )

            if not cpu_metric['Datapoints']:
                cpu_utilization = 'N/A'
            else:
                cpu_utilization = '{:.2f}%'.format(cpu_metric['Datapoints'][0]['Average'])

            # Get the memory utilization for the past 24 hours
            memory_metric = cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='MemoryUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                StartTime=(datetime.utcnow() - timedelta(days=1)).replace(hour=0, minute=0, second=0),
                EndTime=datetime.utcnow().replace(hour=0, minute=0, second=0),
                Period=86400,
                Statistics=['Average']
            )

            if not memory_metric['Datapoints']:
                memory_utilization = 'N/A'
            else:
                memory_utilization = '{:.2f}%'.format(memory_metric['Datapoints'][0]['Average'])

            # Write the instance data and monitoring metrics to the CSV file
            writer.writerow([instance_id, instance_type, state, launch_time, lifecycle, cpu_utilization, memory_utilization])

