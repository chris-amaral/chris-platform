variable "project_name" {
  description = "Nome do projeto utilizado como prefixo nos recursos"
  type        = string
}

variable "environment" {
  description = "Ambiente de deploy (dev, homol, prod)"
  type        = string
}

variable "instance_type" {
  description = "Tipo da instancia EC2 (recomendado: t3.medium para Kind)"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "ID da subnet onde a EC2 sera lancada"
  type        = string
}

variable "security_group_ids" {
  description = "Lista de IDs de Security Groups para a EC2"
  type        = list(string)
}

variable "instance_profile_name" {
  description = "Nome do IAM Instance Profile para a EC2"
  type        = string
}

variable "key_name" {
  description = "Nome de um key pair existente. Deixe vazio para gerar automaticamente"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Tamanho do volume EBS root em GB"
  type        = number
  default     = 30
}

variable "enable_detailed_monitoring" {
  description = "Habilitar CloudWatch detailed monitoring na EC2"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags padrao aplicadas a todos os recursos do modulo"
  type        = map(string)
  default     = {}
}
