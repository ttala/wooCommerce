variable "region" {
  type = string
  default = "pl-waw"
  description = "The scaleway default region"
}

variable "zone" {
  type = string
  default = "pl-waw-1"
  description = "The scaleway default zone"
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
