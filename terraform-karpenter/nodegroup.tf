###################################### deploy node-group and its IAM role and policies##################################

resource "aws_iam_role" "karpenter-nodes" {
  name = "KarpenterNodeRole-${var.cluster_name}"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole", 
        "sts:AssumeRoleWithWebIdentity"
      ]      
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "karpenter-eks-worker-node-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter-nodes.name
}

resource "aws_iam_role_policy_attachment" "karpenter-eks-cni-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter-nodes.name
}

resource "aws_iam_role_policy_attachment" "karpenter-ec2-container-registry-read-only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter-nodes.name
}

resource "aws_iam_role_policy_attachment" "karpenter-ec2-instance-core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter-nodes.name
}

resource "aws_eks_node_group" "private-nodes" {
  cluster_name    = var.cluster_name
  version         = var.cluster_version
  node_group_name = "nodes-for-karpenter"
  node_role_arn   = aws_iam_role.karpenter-nodes.arn

  subnet_ids = module.private-subnets-eks.ids

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "karpenter"
  }

  taint {
    key = "test"
    value = "infinit"
    effect = "NO_SCHEDULE"
  }

  depends_on = [
    aws_iam_role_policy_attachment.karpenter-eks-worker-node-policy,
    aws_iam_role_policy_attachment.karpenter-eks-cni-policy,
    aws_iam_role_policy_attachment.karpenter-ec2-container-registry-read-only,
    aws_iam_role_policy_attachment.karpenter-ec2-instance-core,
  ]

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_iam_instance_profile" "karpenter-profile" {
  name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  role = aws_iam_role.karpenter-nodes.name
}
########################################### deploy karpenter related IAM policies #########################################


resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-policy-${var.cluster_name}"
  role = aws_iam_role.karpenter-nodes.name
  policy = jsonencode({
    "Statement": [
        {
            "Action": [
                "ssm:GetParameter",
                "ec2:DescribeImages",
                "ec2:RunInstances",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeAvailabilityZones",
                "ec2:DeleteLaunchTemplate",
                "ec2:CreateTags",
                "ec2:CreateLaunchTemplate",
                "ec2:CreateFleet",
                "ec2:DescribeSpotPriceHistory",
                "pricing:GetProducts"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "Karpenter"
        },
        {
            "Action": "ec2:TerminateInstances",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/karpenter.sh/provisioner-name": "*"
                }
            },
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "ConditionalEC2Termination"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::${var.aws_account}:role/KarpenterNodeRole-${var.cluster_name}",
            "Sid": "PassNodeIAMRole"
        },
        {
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:aws:eks:${var.aws_region}:${var.aws_account}:cluster/${var.cluster_name}",
            "Sid": "EKSClusterEndpointLookup"
        }
    ],
    "Version": "2012-10-17"
  })
}

resource "aws_iam_policy" "karpenter-sqs" {
  name        = "${var.cluster_name}-karpenter-sqs"
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
        Resource = "arn:aws:sqs:${var.aws_region}:${var.aws_account}:${var.sqs_queue_name}"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "karpenter-sqs" {
  policy_arn = "${aws_iam_policy.karpenter-sqs.arn}"
  role       = aws_iam_role.karpenter-nodes.name
}
