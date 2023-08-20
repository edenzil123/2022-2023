this directory is userd to deploy :
1. nodegroup with taint
2. karpenter with helm
3. their IAM permmisions (without IRSA , so karpenter is using the nodegroup role) 
4. sqs queue and eventbridge rules to detect spot interruptions.
