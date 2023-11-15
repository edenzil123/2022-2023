import boto3
import csv

# Set up AWS session
session = boto3.Session(region_name='us-east-1')
ec2 = session.client('ec2')

# Set up output file
with open('unused_ebs_volumes.csv', 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)

    # Write header row
    writer.writerow(['Volume ID', 'Has Kubernetes tags?', 'Cluster exists?', 'Namespace exists?', 'PVC exists?'])

    # Iterate over all EBS volumes in the region
    for volume in ec2.describe_volumes()['Volumes']:
        if volume['State'] != 'in-use':
            tags = volume['Tags']
            pvc_name = next((tag['Value'] for tag in tags if tag['Key'] == 'kubernetes.io/created-for/pvc/name'), None)
            pvc_namespace = next((tag['Value'] for tag in tags if tag['Key'] == 'kubernetes.io/created-for/pvc/namespace'), None)
            cluster = next((tag['Value'] for tag in tags if tag['Key'].startswith('kubernetes.io/cluster/')), None)

            # Check if volume has the correct Kubernetes tags
            if pvc_name and pvc_namespace and cluster:
                has_kubernetes_tags = 'yes'
            else:
                has_kubernetes_tags = 'no'

            # Check if cluster still exists
            eks = session.client('eks')
            try:
                eks.describe_cluster(name=cluster)
                cluster_exists = 'yes'
            except eks.exceptions.ResourceNotFoundException:
                cluster_exists = 'no'
                namespace_exists = 'no'
                pvc_exists = 'no'
                writer.writerow([volume['VolumeId'], has_kubernetes_tags, cluster_exists, namespace_exists, pvc_exists])
                continue

            # Check if namespace still exists
            try:
                eks.list_namespaced_deployment_jobs(namespace=pvc_namespace)
                namespace_exists = 'yes'
            except eks.exceptions.ResourceNotFoundException:
                namespace_exists = 'no'
                pvc_exists = 'no'
                writer.writerow([volume['VolumeId'], has_kubernetes_tags, cluster_exists, namespace_exists, pvc_exists])
                continue

            # Check if PVC still exists
            try:
                eks.describe_persistent_volume_claim(namespace=pvc_namespace, name=pvc_name)
                pvc_exists = 'yes'
            except eks.exceptions.ResourceNotFoundException:
                pvc_exists = 'no'
            writer.writerow([volume['VolumeId'], has_kubernetes_tags, cluster_exists, namespace_exists, pvc_exists])

