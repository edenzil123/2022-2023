**karpenter spot interruption queue - deployed with ack controllers**

use case: you want karpenter to watch for spot interruptions and get a notice 2 minutes before the spot is lost.  
If enabled, Karpenter will watch for upcoming involuntary interruption events that could affect your nodes (health events, spot interruption, etc.)
and will cordon, drain, and terminate the node(s) ahead of the event to reduce workload disruption. For Spot interruptions, the provisioner will start a new machine as soon as it sees the Spot interruption warning. Spot interruptions have a 2 minute notice before Amazon EC2 reclaims the instance. 

to "catch" the spot interruptions all that karpenter need is the sqs queue *name*, all the rest you need to deploy by yourself. 
the rest is eventBridge rule and sqs queue. in this tutorial we you will deploy it with ack controllers
The eventBridge rule will watch for AWS "EC2 Spot Instance Interruption Warning" and send it to the sqs queue.

**Installing the ack controllers**
```
helm install eventbridge-controller oci://public.ecr.aws/aws-controllers-k8s/eventbridge-chart

helm install sqs-controller oci://public.ecr.aws/aws-controllers-k8s/sqs-chart 

```

after that you need to configure the IAM role to the service accounts of the ack controllers.
i deployed it with terraform:

```terraform
################## IAM Roles for ack sqs #################
data "aws_iam_policy" "ack-sqs" {
  name = "AmazonSQSFullAccess"
}


module "ack-sqs-irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.5.0"

  role_name = "ack-sqs-${local.cluster_name}"

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["aws-controllers:ack-sqs-controller"]
    }
  }

  role_policy_arns = {
    ack-sqs           = data.aws_iam_policy.ack-sqs.arn
  }

}



################## IAM Roles for ack eventbridge #################
data "aws_iam_policy" "ack-eventbridge" {
  name = "AmazonEventBridgeFullAccess"
}Harbor API create proxy cache project · goharbor/harbor · Discussion #14786


module "ack-eventbridge-irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.5.0"

  role_name = "ack-eventbridge-${local.cluster_name}"

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["aws-controllers:ack-eventbridge-controller"]
    }
  }

  role_policy_arns = {
    ack-eventbridge           = data.aws_iam_policy.ack-eventbridge.arn
  }

}

```
MAKE SURE THE NAME OF THE SERVICE ACCOUNT IN THE FILED `namespace_service_accounts` IS THE ONE THE ACK CONTROLLER IS USING.  

Annotate the service accounts:

```bash
kubectl annotate serviceaccount ack-eventbridge-controller eks.amazonaws.com/role-arn=arn:aws:iam::<ACOUNT ID>:role/ack-eventbridge
kubectl annotate serviceaccount ack-sqs-controller eks.amazonaws.com/role-arn=arn:aws:iam::<ACOUNT ID>:role/ack-sqs
```

**Deploying the resources**

After you succesfully installed the ack's and made sure there pods are running you can now configure the sqs queue and the eventbridge rule. 
here are the yamls:

```yaml
apiVersion: sqs.services.k8s.aws/v1alpha1
kind: Queue
metadata:
  name: sqs
  namespace: aws-controllers
spec:
  queueName: sqs
  policy: | 
    {
      "Version": "2012-10-17",
      "Id": "__default_policy_ID",
      "Statement": [
        {
          "Sid": "__owner_statement",
          "Effect": "Allow",
          "Principal": {
            "AWS": "arn:aws:iam::${ACCOUNT-ID}:root"
          },
          "Action": "SQS:*",
          "Resource": "arn:aws:sqs:us-east-1:${ACCOUNT-ID}:sqs"
        },
        {
          "Sid": "AWSEvents_spot-interruption",
          "Effect": "Allow",
          "Principal": {
            "Service": "events.amazonaws.com"
          },
          "Action": "sqs:SendMessage",
          "Resource": "arn:aws:sqs:us-east-1:${ACCOUNT-ID}:sqs",
          "Condition": {
            "ArnEquals": {
              "aws:SourceArn": "arn:aws:events:us-east-1:${ACCOUNT-ID}:rule/spot-interruption"
            }
          }
        }
      ]
    }
 ###################################### eventBridge rule ##################################
apiVersion: eventbridge.services.k8s.aws/v1alpha1
kind: Rule
metadata:
  name: spot-interruption
  namespace: aws-controllers
spec:
  name: spot-interruption
  targets:
  - arn: arn:aws:sqs:us-east-1:${ACCOUNT-ID}:sqs
    id: sqs
  eventPattern: | 
    {
      "source": ["aws.ec2"],
      "detail-type": ["EC2 Spot Instance Interruption Warning"]
    }
 
```
In the queue configuration you have to give permmisions to the eventbridge rule to send messeges to him.
And in the eventBridge rule set the sqs queue as the target. 

**Karpenter's side configurations**

Now you need to add an IAM policy to karpenter's service account permmisions to access and read the sqs queue.
I added it with terraform:

```terraform

resource "aws_iam_policy" "karpenter-sqs" {
  name        = "${data.aws_eks_cluster.cluster.id}-karpenter-sqs"
  description = "SQS permissions added to karpenter policy to detect spot interruptions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "SQS:DeleteMessage",
          "SQS:ReceiveMessage",
          "SQS:GetQueueAttributes",
          "SQS:GetQueueUrl"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:sqs:${var.region}:${data.aws_organizations_organization.org.accounts[0].id}:sqs"
      }   
    ]
  })

  tags = data.aws_eks_cluster.cluster.tags
}

```

Finally, add the "aws.interruptionQueueName" setting to karpnter, i installed it with helm so i added ti the values.yaml file this:
```yaml
settings:
  aws:
    interruptionQueueName: "sqs"
```
check in the logs of karpenter's pod if he find the queue anddd
Thats it! good luck.
