variable "project_name" {
  description = "Nome do projeto utilizado como prefixo nos recursos"
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

variable "aws_region" {
  description = "Regiao AWS onde os recursos serao criados"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr deve ser um CIDR valido (ex: 10.0.0.0/16)."
  }
}

variable "public_subnet_cidr" {
  description = "Bloco CIDR da subnet publica"
  type        = string
  default     = "10.0.1.0/24"
}

variable "tags" {
  description = "Tags padrao aplicadas a todos os recursos do modulo"
  type        = map(string)
  default     = {}
}
