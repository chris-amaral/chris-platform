variable "project_name" {
  description = "Nome do projeto utilizado como prefixo nos recursos"
  type        = string
}

variable "environment" {
  description = "Ambiente de deploy (dev, homol, prod)"
  type        = string
}

variable "github_repository" {
  description = "Repositorio GitHub no formato owner/repo para trust policy do OIDC"
  type        = string
}

variable "tags" {
  description = "Tags padrao aplicadas a todos os recursos do modulo"
  type        = map(string)
  default     = {}
}
