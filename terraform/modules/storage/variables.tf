variable "project_name" {
  description = "Nome do projeto usado para nomear bucket e tabela"
  type        = string
}

variable "tags" {
  description = "Tags padrao aplicadas a todos os recursos do modulo"
  type        = map(string)
  default     = {}
}
