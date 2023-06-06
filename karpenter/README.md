**karpenter spot interruption queue - deployed with ack controllers**

use case: If enabled, Karpenter will watch for upcoming involuntary interruption events that could affect your nodes (health events, spot interruption, etc.)
and will cordon, drain, and terminate the node(s) ahead of the event to reduce workload disruption. 

to "catch" the spot interruptions all that karpenter need is the sqs queue *name*, all the rest you need to deploy by yourself. 
the rest is eventBridge rule and sqs queue. in this tutorial we you will deploy it with ack controllers


**installing the ack controllers**
```
helm install eventbridge-controller oci://public.ecr.aws/aws-controllers-k8s/eventbridge-chart

helm install sqs-controller oci://public.ecr.aws/aws-controllers-k8s/sqs-chart 

```

after that you need to configure the iam role to give to the service accounts of the ack controllers.
i deployed it with terraform:

```terraform


```
