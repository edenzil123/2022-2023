**karpenter spot interruption queue - deployed with ack controllers**

use case: If enabled, Karpenter will watch for upcoming involuntary interruption events that could affect your nodes (health events, spot interruption, etc.)
and will cordon, drain, and terminate the node(s) ahead of the event to reduce workload disruption. For Spot interruptions, the provisioner will start a new machine as soon as it sees the Spot interruption warning. Spot interruptions have a 2 minute notice before Amazon EC2 reclaims the instance. 

to "catch" the spot interruptions all that karpenter need is the sqs queue *name*, all the rest you need to deploy by yourself. 
the rest is eventBridge rule and sqs queue. in this tutorial we you will deploy it with ack controllers


**installing the ack controllers**
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
}


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


