variable "project_name" {
  description = "Nome do projeto utilizado como prefixo nos recursos"
  type        = string
}

variable "environment" {
  description = "Ambiente de deploy (dev, homol, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde o Security Group sera criado"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "Lista de CIDRs autorizados para acesso SSH e Kubernetes API"
  type        = list(string)
  default     = []
}

variable "enable_nodeport_access" {
  description = "Habilitar acesso ao range de NodePort (30000-32767) dos CIDRs permitidos"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags padrao aplicadas a todos os recursos do modulo"
  type        = map(string)
  default     = {}
}
