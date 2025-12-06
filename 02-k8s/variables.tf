variable "db_password_secret_id" {
  type        = string
  description = "Scaleway Secret ID for DB password"
}

variable "db_name" {
  type = string
  default = "rdb"
}

variable "admin_email" {
  type = string
  default = "contact@kerocam.com"
}

variable "docker_image" {
  type = string
  default = "rg.pl-waw.scw.cloud/ns-woocom/woocommerce:latest"
}
