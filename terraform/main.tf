###############################################################################
# Root Module - Orchestration
# Composes all infrastructure modules with dependency injection.
# Author: Christopher Amaral
###############################################################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Squad       = var.squad
    ManagedBy   = "terraform"
    Owner       = "christopher.amaral"
  }
}

# --- Networking -------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  tags               = local.common_tags
}

# --- Security ---------------------------------------------------------------
module "security" {
  source = "./modules/security"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.networking.vpc_id
  allowed_ssh_cidrs      = var.allowed_ssh_cidrs
  enable_nodeport_access = var.enable_nodeport_access
  tags                   = local.common_tags
}

# --- Storage (Terraform State) ----------------------------------------------
module "storage" {
  source = "./modules/storage"

  project_name = var.project_name
  tags         = local.common_tags
}

# --- IAM --------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  project_name      = var.project_name
  environment       = var.environment
  github_repository = var.github_repository
  tags              = local.common_tags
}

# --- Compute ----------------------------------------------------------------
module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  instance_type         = var.instance_type
  subnet_id             = module.networking.public_subnet_id
  security_group_ids    = [module.security.k8s_node_sg_id]
  instance_profile_name = module.iam.ec2_instance_profile_name
  key_name              = var.key_name
  tags                  = local.common_tags
}
