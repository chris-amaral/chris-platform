###############################################################################
# Module: security
# Description: Security Groups for EC2 instances.
#              Follows least-privilege: only SSH and K8s API from allowed CIDRs.
# Author: Christopher Amaral
###############################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# --- Security Group (EC2 K8s Dev) -------------------------------------------
resource "aws_security_group" "k8s_node" {
  name        = "${local.name_prefix}-k8s-node-sg"
  description = "SG for Kubernetes dev node - SSH and K8s API restricted to allowed CIDRs"
  vpc_id      = var.vpc_id

  # SSH - restricted to admin CIDRs only
  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "SSH access from admin CIDRs"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
    }
  }

  # Kubernetes API - same restriction as SSH
  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "Kubernetes API from admin CIDRs"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
    }
  }

  # NodePort range - optional, for testing via browser
  dynamic "ingress" {
    for_each = var.enable_nodeport_access ? [1] : []
    content {
      description = "NodePort range for service testing"
      from_port   = 30000
      to_port     = 32767
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
    }
  }

  # Egress - required for apt, docker pulls, helm repos
  egress {
    description = "All outbound traffic (package managers, container registries)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-k8s-node-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}
