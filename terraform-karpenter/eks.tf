resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter/"
  chart      = "karpenter"
  version    = "v0.27.3"
  values = [<<-EOF
    serviceAccount:
      name: "karpenter"
    settings:
      aws:
        interruptionQueueName: "${var.sqs_queue_name}"
        defaultInstanceProfile: "${aws_iam_instance_profile.karpenter-profile.name}"
        clusterName: "${var.cluster_name}"
        clusterEndpoint: ${module.eks.eks_endpoint}
    serviceMonitor:
      enabled: true
    nodeSelector:
      role: karpenter
    tolerations:
      - key: test
        operator: Exists
        effect: "NoSchedule"
EOF
  ]
  depends_on = [aws_eks_node_group.private-nodes]
}


