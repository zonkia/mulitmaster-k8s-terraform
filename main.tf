provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "kubernetes.io/cluster/kubernetes" = "owned"
    }
  }
}

data "aws_ami" "amazon-linux2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Key pair--------------------------------

resource "tls_private_key" "terra-private-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "terra-key-pair" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.terra-private-key.public_key_openssh
}

resource "local_file" "terra-ssh-key" {
  filename = "${aws_key_pair.terra-key-pair.key_name}.pem"
  content = tls_private_key.terra-private-key.private_key_pem
}

# VPC--------------------------------

resource "aws_vpc" "terra-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"

  tags = {
    Name = "terra-vpc"
  }
}

# Subnets--------------------------------

resource "aws_subnet" "terra-public-subnet1" {
  vpc_id                  = aws_vpc.terra-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "terra-public-subnet1"
  }
}

resource "aws_subnet" "terra-public-subnet2" {
  vpc_id                  = aws_vpc.terra-vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "terra-public-subnet2"
  }
}

resource "aws_subnet" "terra-public-subnet3" {
  vpc_id                  = aws_vpc.terra-vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = true

  tags = {
    Name = "terra-public-subnet3"
  }
}

resource "aws_subnet" "terra-private-subnet1" {
  vpc_id            = aws_vpc.terra-vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "terra-private-subnet1"
  }
}

resource "aws_subnet" "terra-private-subnet2" {
  vpc_id            = aws_vpc.terra-vpc.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "terra-private-subnet2"
  }
}

resource "aws_subnet" "terra-private-subnet3" {
  vpc_id            = aws_vpc.terra-vpc.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "terra-private-subnet3"
  }
}
# Internet gateway--------------------------------

resource "aws_internet_gateway" "terra-igw" {
  vpc_id = aws_vpc.terra-vpc.id

  tags = {
    Name = "terra-igw"
  }
}
#route tables--------------------------------

resource "aws_route_table" "terra-public-rt" {
  vpc_id = aws_vpc.terra-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terra-igw.id
  }

  tags = {
    Name = "terra-public-rt"
  }
}

resource "aws_route_table" "terra-private-rt" {
  vpc_id = aws_vpc.terra-vpc.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.terra-nat-instance.primary_network_interface_id
  }

  tags = {
    Name = "terra-private-rt"
  }
}
# Subnets to Route Tables associations--------------------------------

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.terra-public-subnet1.id
  route_table_id = aws_route_table.terra-public-rt.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.terra-public-subnet2.id
  route_table_id = aws_route_table.terra-public-rt.id
}
resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.terra-public-subnet3.id
  route_table_id = aws_route_table.terra-public-rt.id
}
resource "aws_route_table_association" "d" {
  subnet_id      = aws_subnet.terra-private-subnet1.id
  route_table_id = aws_route_table.terra-private-rt.id
}
resource "aws_route_table_association" "e" {
  subnet_id      = aws_subnet.terra-private-subnet2.id
  route_table_id = aws_route_table.terra-private-rt.id
}
resource "aws_route_table_association" "f" {
  subnet_id      = aws_subnet.terra-private-subnet3.id
  route_table_id = aws_route_table.terra-private-rt.id
}

# Security groups--------------------------------

resource "aws_security_group" "terra-front-sg" {
  name   = "terra-front-sg"
  vpc_id = aws_vpc.terra-vpc.id
  ingress {
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = var.https_port
    to_port     = var.https_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    from_port   = 30000
    to_port     = 32000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "terra-back-sg" {
  name   = "terra-back-sg"
  vpc_id = aws_vpc.terra-vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "terra-nat-sg" {
  name   = "terra-nat-sg"
  vpc_id = aws_vpc.terra-vpc.id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  }
  ingress {
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  }
  ingress {
    from_port   = var.https_port
    to_port     = var.https_port
    protocol    = "tcp"
    cidr_blocks = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  }
  ingress {
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Master nodes IAM --------------------------------

resource "aws_iam_policy" "terra-master-node-policy" {
  name        = "Kubeadm-Master-Node-Policy"
  path        = "/"
  description = "Policy for master nodes"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "ec2:DescribeInstances",
                "ec2:DescribeRegions",
                "ec2:DescribeRouteTables",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVolumes",
                "ec2:CreateSecurityGroup",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:ModifyInstanceAttribute",
                "ec2:ModifyVolume",
                "ec2:AttachVolume",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:CreateRoute",
                "ec2:DeleteRoute",
                "ec2:DeleteSecurityGroup",
                "ec2:DeleteVolume",
                "ec2:DetachVolume",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DescribeVpcs",
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:AttachLoadBalancerToSubnets",
                "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateLoadBalancerPolicy",
                "elasticloadbalancing:CreateLoadBalancerListeners",
                "elasticloadbalancing:ConfigureHealthCheck",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:DeleteLoadBalancerListeners",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DetachLoadBalancerFromSubnets",
                "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
                "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:CreateTargetGroup",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:DeleteTargetGroup",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeLoadBalancerPolicies",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
                "iam:CreateServiceLinkedRole",
                "kms:DescribeKey",
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "iam:ListInstanceProfiles",
                "iam:AttachRolePolicy",
                "elasticfilesystem:CreateFileSystem",
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:PutLifecycleConfiguration",
                "elasticfilesystem:CreateMountTarget",
                "elasticfilesystem:CreateAccessPoint",
                "elasticfilesystem:DescribeAccessPoints",
                "acm:ListCertificates"

            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:TerminateInstances"
            ],
            "Resource": "*",
            "Condition": {
              "StringLike": {
                "ec2:ResourceTag/Name": "Kube-First-Master-Node"
              }
            }            
        }
    ]
  })
}

resource "aws_iam_role" "terra-master-node-role" {
  name = "Kubeadm-Master-Node-Role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sts:AssumeRole"
        ],
        "Principal" : {
          "Service" : [
            "ec2.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "mastanc-terra-master-node-policy-attatchment" {
  name       = "KubeadmMasterNodeAttatchment"
  roles      = [aws_iam_role.terra-master-node-role.name]
  policy_arn = aws_iam_policy.terra-master-node-policy.arn
}

resource "aws_iam_instance_profile" "terra-master-node-profile" {
  name = "KubeadmMasterNodeProfile"
  role = aws_iam_role.terra-master-node-role.name
}

# Worker nodes IAM --------------------------------

resource "aws_iam_policy" "terra-worker-node-policy" {
  name        = "Kubeadm-Worker-Node-Policy"
  path        = "/"
  description = "Policy for worker nodes"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeRegions",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:BatchGetImage",
                "elasticfilesystem:DescribeMountTargets",
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup"
            ],
            "Resource": "*"
        }
    ]
  })
}

resource "aws_iam_role" "terra-worker-node-role" {
  name = "Kubeadm-Worker-Node-Role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sts:AssumeRole"
        ],
        "Principal" : {
          "Service" : [
            "ec2.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "mastanc-terra-worker-node-policy-attatchment" {
  name       = "KubeadmWorkerNodeAttatchment"
  roles      = [aws_iam_role.terra-worker-node-role.name]
  policy_arn = aws_iam_policy.terra-worker-node-policy.arn
}

resource "aws_iam_instance_profile" "terra-worker-node-profile" {
  name = "KubeadmWorkerNodeProfile"
  role = aws_iam_role.terra-worker-node-role.name
}

# NAT instance --------------------------------

resource "aws_instance" "terra-nat-instance" {
  ami               = data.aws_ami.amazon-linux2.id
  instance_type     = var.instance_size
  user_data         = file("data_nat.sh")
  key_name          = var.key_pair_name
  tags              = { Name = "terra-nat-instance" }
  subnet_id         = aws_subnet.terra-public-subnet2.id
  security_groups   = ["${aws_security_group.terra-nat-sg.id}"]
  source_dest_check = false
}   

# Haproxy instance --------------------------------

resource "aws_instance" "terra-haproxy-instance" {
  ami               = data.aws_ami.amazon-linux2.id
  instance_type     = var.instance_size
  user_data = templatefile("data_haproxy.sh", {
    region                 = var.region
    key_pair               = tls_private_key.terra-private-key.private_key_pem
    key_pair_name          = var.key_pair_name
  })
  key_name          = var.key_pair_name
  tags              = { Name = "Kube-Haproxy-Instance" }
  subnet_id         = aws_subnet.terra-public-subnet1.id
  security_groups   = ["${aws_security_group.terra-front-sg.id}"]
  depends_on = [
    aws_autoscaling_group.terra-asg-master
  ]
  iam_instance_profile = aws_iam_instance_profile.terra-worker-node-profile.name
} 

# Initial Master instance --------------------------------

resource "aws_instance" "terra-master-instance" {
  ami               = data.aws_ami.amazon-linux2.id
  instance_type     = var.master_node_size
  user_data = templatefile("data_firstmaster.sh", {
    cni                    = var.cni
    region                 = var.region
    key_pair               = tls_private_key.terra-private-key.private_key_pem
    key_pair_name          = var.key_pair_name
  })
  key_name          = var.key_pair_name
  tags              = { 
    "Name" = "Kube-First-Master-Node"
    "kubernetes.io/cluster/kubernetes" = "owned"
    "Function" = "Master"
    }
  subnet_id         = aws_subnet.terra-public-subnet1.id
  security_groups   = ["${aws_security_group.terra-front-sg.id}"]
  iam_instance_profile = aws_iam_instance_profile.terra-master-node-profile.name
  depends_on = [
    aws_instance.terra-nat-instance
  ]
} 

# Launch config for master nodes --------------------------------

resource "aws_launch_configuration" "terra-master-lc" {
  name                 = "terra-master-nodes"
  image_id             = data.aws_ami.amazon-linux2.id
  instance_type        = var.master_node_size
  security_groups      = ["${aws_security_group.terra-front-sg.id}"]
  key_name             = var.key_pair_name
  user_data = templatefile("data_master.sh", {
    region                 = var.region
    key_pair               = tls_private_key.terra-private-key.private_key_pem
    key_pair_name          = var.key_pair_name
  })
  iam_instance_profile = aws_iam_instance_profile.terra-master-node-profile.name
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_instance.terra-master-instance
  ]
}

# Autoscaling group for master nodes --------------------------------

resource "aws_autoscaling_group" "terra-asg-master" {
  name                 = "terra-asg-master"
  launch_configuration = aws_launch_configuration.terra-master-lc.id
  min_size             = var.number_of_master_nodes
  max_size             = var.number_of_master_nodes
  desired_capacity     = var.number_of_master_nodes
  health_check_type    = "ELB"
  vpc_zone_identifier  = [aws_subnet.terra-public-subnet1.id, aws_subnet.terra-public-subnet2.id, aws_subnet.terra-public-subnet3.id]
  tag {
    key                 = "Name"
    value               = "Kube-Master-Node"
    propagate_at_launch = true
  }
  tag {
    key                 = "Function"
    value               = "Master"
    propagate_at_launch = true
  }
  tag {
    key                 = "kubernetes.io/cluster/kubernetes"
    value               = "owned"
    propagate_at_launch = true
  }
}
# Launch config for worker nodes --------------------------------

resource "aws_launch_configuration" "terra-worker-lc" {
  name                 = "terra-worker-nodes"
  image_id             = data.aws_ami.amazon-linux2.id
  instance_type        = var.worker_node_size
  security_groups      = ["${aws_security_group.terra-front-sg.id}"]
  key_name             = var.key_pair_name
  user_data = templatefile("data_worker.sh", {
    region                 = var.region
    key_pair               = tls_private_key.terra-private-key.private_key_pem
    key_pair_name          = var.key_pair_name
  })
  iam_instance_profile = aws_iam_instance_profile.terra-worker-node-profile.name
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_launch_configuration.terra-master-lc
  ]
}

# Autoscaling group for worker nodes --------------------------------

resource "aws_autoscaling_group" "terra-asg-worker" {
  name                 = "terra-asg-worker"
  launch_configuration = aws_launch_configuration.terra-worker-lc.id
  min_size             = var.number_of_worker_nodes
  max_size             = 10
  desired_capacity     = var.number_of_worker_nodes
  health_check_type    = "ELB"
  vpc_zone_identifier  = [aws_subnet.terra-private-subnet1.id, aws_subnet.terra-private-subnet2.id, aws_subnet.terra-private-subnet3.id]
  tag {
    key                 = "Name"
    value               = "Kube-Worker-Node"
    propagate_at_launch = true
  }
  tag {
    key                 = "kubernetes.io/cluster/kubernetes"
    value               = "owned"
    propagate_at_launch = true
  }
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }
  tag {
    key                 = "k8s.io/cluster-autoscaler/kubernetes"
    value               = "owned"
    propagate_at_launch = true
  }
}

# Launch config for monitoring nodes --------------------------------

resource "aws_launch_configuration" "terra-monitoring-lc" {
  name                 = "terra-monitoring-nodes"
  image_id             = data.aws_ami.amazon-linux2.id
  instance_type        = var.monitoring_node_size
  security_groups      = ["${aws_security_group.terra-front-sg.id}"]
  key_name             = var.key_pair_name
  user_data = templatefile("data_monitoring.sh", {
    region                 = var.region
    key_pair               = tls_private_key.terra-private-key.private_key_pem
    key_pair_name          = var.key_pair_name
  })
  iam_instance_profile = aws_iam_instance_profile.terra-worker-node-profile.name
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_autoscaling_group.terra-asg-master
  ]
}

# Autoscaling group for monitoring nodes--------------------------------

resource "aws_autoscaling_group" "terra-asg-monitoring" {
  name                 = "terra-asg-monitoring"
  launch_configuration = aws_launch_configuration.terra-monitoring-lc.id
  min_size             = var.number_of_monitoring_nodes
  max_size             = 10
  desired_capacity = var.number_of_monitoring_nodes
  health_check_type    = "ELB"
  vpc_zone_identifier  = [aws_subnet.terra-private-subnet1.id, aws_subnet.terra-private-subnet2.id, aws_subnet.terra-private-subnet3.id]
  tag {
    key                 = "Name"
    value               = "Kube-Monitoring-Node"
    propagate_at_launch = true
  }
  tag {
    key                 = "kubernetes.io/cluster/kubernetes"
    value               = "owned"
    propagate_at_launch = true
  }
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }
  tag {
    key                 = "k8s.io/cluster-autoscaler/kubernetes"
    value               = "owned"
    propagate_at_launch = true
  }
}