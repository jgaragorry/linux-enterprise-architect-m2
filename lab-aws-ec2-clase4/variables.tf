variable "aws_region" {
  description = "Región AWS más cercana a Chile"
  type        = string
  default     = "sa-east-1"
}

variable "instance_type" {
  description = "Instancia Graviton2 (arm64) enfocada en eficiencia y Free Tier"
  type        = string
  default     = "t4g.micro"
}

variable "admin_username" {
  description = "Usuario administrador con acceso SSH y sudo"
  type        = string
  default     = "gmt"
}

variable "ssh_ingress_cidr" {
  description = "CIDR permitido para SSH (restringe a tu IP pública /32 en producción)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "extra_ebs_size_gb" {
  description = "Tamaño en GB del disco EBS adicional gp3"
  type        = number
  default     = 10
}

variable "finops_tags" {
  description = "Etiquetas obligatorias de FinOps y gobernanza"
  type        = map(string)
  default = {
    Environment = "lab"
    Project     = "sre-linux-lab"
    Owner       = "gmt"
    CostCenter  = "engineering-labs"
    ManagedBy   = "terraform"
    Workload    = "ubuntu-2604-graviton2"
  }
}
