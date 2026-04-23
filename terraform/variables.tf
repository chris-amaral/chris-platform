###############################################################################
# Root Variables
# Valores injetados via inventories/<env>/terraform.tfvars
# Author: Christopher Amaral
###############################################################################

# --- General ----------------------------------------------------------------
variable "aws_region" {
  description = "Regiao AWS para provisionamento dos recursos"
  type        = string
}

variable "project_name" {
  description = "Nome do projeto (usado como prefixo em todos os recursos)"
  type        = string
}

variable "environment" {
  description = "Ambiente de deploy (dev, homol, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "homol", "prod"], var.environment)
    error_message = "Environment deve ser: dev, homol ou prod."
  }
}

variable "squad" {
  description = "Nome da squad responsavel pelo projeto"
  type        = string
}

variable "owner" {
  description = "Responsavel pelo projeto (usado nas tags)"
  type        = string
  default     = "devops"
}

# --- Networking -------------------------------------------------------------
variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Bloco CIDR da subnet publica"
  type        = string
  default     = "10.0.1.0/24"
}

# --- Compute ----------------------------------------------------------------
variable "instance_type" {
  description = "Tipo da instancia EC2"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Nome de um key pair SSH existente (vazio = gera automaticamente)"
  type        = string
  default     = ""
}

# --- Security ---------------------------------------------------------------
variable "allowed_ssh_cidrs" {
  description = "CIDRs autorizados para SSH e acesso ao Kubernetes API"
  type        = list(string)
  default     = []
}

variable "enable_nodeport_access" {
  description = "Liberar range de NodePort (30000-32767) dos CIDRs permitidos"
  type        = bool
  default     = false
}

# --- IAM / CI ---------------------------------------------------------------
variable "github_repository" {
  description = "Repositorio GitHub (owner/repo) para OIDC trust policy"
  type        = string
}
