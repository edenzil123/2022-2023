import boto3
import csv

# Connect to AWS Elastic Load Balancing client
elb_client = boto3.client('elb')
elbv2_client = boto3.client('elbv2')

# Retrieve all Classic Load Balancers
response = elb_client.describe_load_balancers()

# Retrieve all Application Load Balancers and Network Load Balancers
response_v2 = elbv2_client.describe_load_balancers()

# Define the headers for the CSV file
headers = ['Load Balancer Name', 'Type', 'DNS Name', 'State', 'Registered Instances', 'Instance States']

# Open CSV file for writing and write headers
with open('elb_status.csv', 'w') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow(headers)

    # Loop through all Classic Load Balancers
    for load_balancer in response['LoadBalancerDescriptions']:
        # Retrieve the Load Balancer name and DNS name
        lb_name = load_balancer['LoadBalancerName']
        dns_name = load_balancer['DNSName']
        lb_type = 'Classic'

        # Retrieve the state of the Load Balancer
        if 'State' in load_balancer:
            state = load_balancer['State']['Code']
        else:
            state = 'N/A'

        # Retrieve the instances registered to the Load Balancer
        registered_instances = []
        instance_states = []

        for instance in load_balancer['Instances']:
            registered_instances.append(instance['InstanceId'])

            instance_state_response = elb_client.describe_instance_health(LoadBalancerName=lb_name, Instances=[instance])
            instance_state = instance_state_response['InstanceStates'][0]['State']
            instance_states.append(instance_state)

        # Write the Load Balancer information to the CSV file
        writer.writerow([lb_name, lb_type, dns_name, state, 'Yes' if registered_instances else 'No', instance_states if registered_instances else 'N/A'])

    # Loop through all Application Load Balancers and Network Load Balancers
    for load_balancer in response_v2['LoadBalancers']:
        # Retrieve the Load Balancer name, type, and DNS name
        lb_name = load_balancer['LoadBalancerName']
        lb_type = load_balancer['Type']
        dns_name = load_balancer['DNSName']

        # Retrieve the state of the Load Balancer
        if 'State' in load_balancer:
            state = load_balancer['State']['Code']
        else:
            state = 'N/A'

        # Retrieve the instances registered to the Load Balancer
        target_groups = elbv2_client.describe_target_groups(LoadBalancerArn=load_balancer['LoadBalancerArn'])
        registered_instances = []
        instance_states = []

        for target_group in target_groups['TargetGroups']:
            target_group_arn = target_group['TargetGroupArn']
            target_group_health = elbv2_client.describe_target_health(TargetGroupArn=target_group_arn)

            for target in target_group_health['TargetHealthDescriptions']:
                registered_instances.append(target['Target']['Id'])
                instance_states.append(target['TargetHealth']['State'])

        # Write the Load Balancer information to the CSV file
        writer.writerow([lb_name, lb_type, dns_name, state, 'Yes' if registered_instances else 'No', instance_states if registered_instances else 'N/A'])

