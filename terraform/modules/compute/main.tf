###############################################################################
# Module: compute
# Description: EC2 instance with Kind cluster pre-configured via user-data.
#              Includes SSH key pair generation (optional) and encrypted EBS.
# Author: Christopher Amaral
###############################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  key_name    = var.key_name != "" ? var.key_name : aws_key_pair.generated[0].key_name
}

# --- AMI Data Source (Ubuntu 22.04 LTS - Canonical) -------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical official

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
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

# --- SSH Key Pair (auto-generated when key_name is empty) -------------------
resource "tls_private_key" "generated" {
  count     = var.key_name == "" ? 1 : 0
  algorithm = "ED25519"
}

resource "aws_key_pair" "generated" {
  count      = var.key_name == "" ? 1 : 0
  key_name   = "${local.name_prefix}-key"
  public_key = tls_private_key.generated[0].public_key_openssh

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-key"
  })
}

# --- EC2 Instance -----------------------------------------------------------
resource "aws_instance" "k8s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name
  key_name               = local.key_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${local.name_prefix}-k8s-node-ebs"
    })
  }

  user_data                   = file("${path.module}/scripts/bootstrap-cluster.sh")
  user_data_replace_on_change = false

  # IMDSv2 enforced - prevents SSRF-based credential theft
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring = var.enable_detailed_monitoring

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-k8s-node"
    Role = "kubernetes-dev"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
