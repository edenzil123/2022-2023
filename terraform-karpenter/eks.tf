### EKS
module "eks" {
  source             = "../../modules/eks/"
  main_vpc_id        = module.vpc.vpc_id
  vpc_cidr_block     = var.processing_vpc_cidr
  availability_zones = var.availability_zones
  project_name       = var.project_name
  cluster_name       = var.cluster_name
  kubernetes_version = var.cluster_version
  subnets_id         = module.private-subnets.ids
  aws_region         = var.aws_region
  environment_name   = var.environment_name
  source_sg_id       = aws_security_group.eks-node.id
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = module.eks.eks_id
  addon_name        = "vpc-cni"
  addon_version     = "v1.11.4-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name      = module.eks.eks_id
  addon_name        = "coredns"
  addon_version     = "v1.8.7-eksbuild.3"
  resolve_conflicts = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = module.eks.eks_id
  addon_name        = "kube-proxy"
  addon_version     = "v1.23.8-eksbuild.2"
  resolve_conflicts = "OVERWRITE"
}

### Data source: EKS Compatible AMI
data "aws_ami" "eks-node" {
  executable_users = ["all"]
  owners           = ["amazon"]
  most_recent      = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

### SecurityGroup: eks-node
resource "aws_security_group" "eks-node" {
  name        = "${var.project_name}-eks-node-sg" #FIXME: Rename to -node
  description = "Security group for all nodes in the EKS cluster"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "kubernetes.io/cluster/${var.project_name}-eks" = "owned"
    Name                                            = "${var.project_name}-eks-node-sg"
    Project                                         = var.project_name
    Environment                                     = var.environment_name
    Managed_by                                      = "terraform"
  }
}

# SecurityGroup rule: Allow node to communicate with each other
resource "aws_security_group_rule" "eks-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.eks-node.id
  source_security_group_id = aws_security_group.eks-node.id
  to_port                  = 65535
  type                     = "ingress"
}

# SecurityGroup rule: Allow node to communicate from the cluster control plane
resource "aws_security_group_rule" "eks-node-ingress-control-panel" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.eks-node.id
  source_security_group_id = module.eks.eks_sg_id
  to_port                  = 65535
  type                     = "ingress"
}

# Security Group rule: full access from VPN
resource "aws_security_group_rule" "vpn" {
  type              = "ingress"
  description       = "VPN"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["10.25.0.0/16"]
  security_group_id = aws_security_group.eks-node.id
}

data "tls_certificate" "processing" {
  url = module.eks.eks_openid_provider_url
}

resource "aws_iam_openid_connect_provider" "processing" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.processing.certificates[0].sha1_fingerprint]
  url             = module.eks.eks_openid_provider_url
}

module "alb-controller" {
  source                       = "../../modules/aws-load-balancer-controller"
  eks_cluster_name             = module.eks.eks_id
  iam_openid_provider_arn      = aws_iam_openid_connect_provider.processing.arn
  iam_openid_provider_url      = aws_iam_openid_connect_provider.processing.url
  ingress_service_account_name = "alb-ingress-controller"
  namespace                    = "kube-system"
  vpcId                        = module.vpc.vpc_id
}

module "ebs-csi-driver" {
  source                   = "../../modules/aws-ebs-csi-driver"
  eks_cluster_name         = module.eks.eks_id
  iam_openid_provider_arn  = aws_iam_openid_connect_provider.processing.arn
  iam_openid_provider_url  = aws_iam_openid_connect_provider.processing.url
  ebs_service_account_name = "ebs-csi-driver"
  namespace                = "kube-system"
}

resource "helm_release" "external-dns" {
  name              = "external-dns"
  repository        = "https://kubernetes-sigs.github.io/external-dns"
  chart             = "external-dns"
  namespace         = "kube-system"
  version           = "1.11.0"
  dependency_update = true
  values = [<<EOF
    image:
      tag: v0.12.2
    logLevel: debug
    provider: cloudflare
    env:
      - name: CF_API_TOKEN
        valueFrom:
          secretKeyRef:
            name: cloudflare-api-token
            key: api_token
    extraArgs:
      - --zone-id-filter=5a07cce7d24d546f322fe11bd2944b80
    domainFilters:
      - raycatch.com
    nodeSelector:
      pool: master
    policy: upsert-only
EOF
  ]
}

resource "helm_release" "k8s-prom-stack" {
  name       = "prom-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "kube-system"
  version    = "45.27.1"
  values = [<<-EOF
    defaultRules:
      rules:
        alertmanager: false
        etcd: false
        configReloaders: false
        general: false
        k8s: true
        kubeApiserver: false
        kubeApiserverAvailability: true
        kubeApiserverSlos: true
        kubeControllerManager: false
        kubelet: true
        kubeProxy: true
        kubePrometheusGeneral: true
        kubePrometheusNodeRecording: true
        kubernetesApps: false
        kubernetesResources: false
        kubernetesStorage: false
        kubernetesSystem: false
        kubeSchedulerAlerting: false
        kubeSchedulerRecording: false
        kubeStateMetrics: false
        network: false
        node: true
        nodeExporterAlerting: false
        nodeExporterRecording: true
        prometheus: false
        prometheusOperator: false
    prometheus:
      ingress:
        enabled: true
        ingressClassName: alb
        annotations:
          alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30,load_balancing.algorithm.type=least_outstanding_requests
          alb.ingress.kubernetes.io/target-type: ip
          alb.ingress.kubernetes.io/scheme: internal
          alb.ingress.kubernetes.io/load-balancer-name: infrastructure-aws-alb
          alb.ingress.kubernetes.io/group.name: infrastructure
          alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-central-1:293578476393:certificate/866a5d8c-ceaf-4158-9feb-e00200fd19be
          alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
          alb.ingress.kubernetes.io/ssl-redirect: '443'
          alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
          alb.ingress.kubernetes.io/healthcheck-port: traffic-port
          alb.ingress.kubernetes.io/success-codes: 200-299,302
        hosts: ["prometheus.raycatch.com"]
        paths: ["/*"]
        pathType: ImplementationSpecific
        tls:
          - secretName: prometheus.raycatch.com
            hosts: ["prometheus.raycatch.com"]
      prometheusSpec:
        retention: 10d
        nodeSelector:
          pool: master
          "topology.kubernetes.io/zone": eu-central-1c
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: gp3
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 50Gi
    alertmanager:
      enabled: false
    grafana:
      ingress:
        enabled: true
        ingressClassName: alb
        annotations:
          alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30,load_balancing.algorithm.type=least_outstanding_requests
          alb.ingress.kubernetes.io/target-type: ip
          alb.ingress.kubernetes.io/scheme: internal
          alb.ingress.kubernetes.io/load-balancer-name: infrastructure-aws-alb
          alb.ingress.kubernetes.io/group.name: infrastructure
          alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-central-1:293578476393:certificate/866a5d8c-ceaf-4158-9feb-e00200fd19be
          alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
          alb.ingress.kubernetes.io/ssl-redirect: '443'
          alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
          alb.ingress.kubernetes.io/healthcheck-port: traffic-port
          alb.ingress.kubernetes.io/success-codes: 200-299
        hosts: ["grafana.raycatch.com"]
        path: /
        tls:
          - secretName: grafana.raycatch.com
            hosts: ["grafana.raycatch.com"]
      nodeSelector:
        pool: master
      grafana.ini:
        server:
          domain: grafana.raycatch.com
          root_url: https://grafana.raycatch.com
        auth.anonymous:
          enabled: true
          org_role: Viewer
      adminPassword: prom-operator
    prometheusOperator:
      nodeSelector:
        pool: master
      tls:
        enabled: false
      admissionWebhooks:
        enabled: false
        patch:
          enabled: false
EOF
  ]
}

### Outputs
output "eks_kubeconfig" {
  value = module.eks.kubeconfig
}

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

# vim:filetype=terraform ts=2 sw=2 et:
