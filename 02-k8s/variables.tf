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

variable "domain" {
  type = string
  default = "kerocam.com"
}

variable "subdomain" {
  type = string
  default = "woo"
}

variable "admin_email" {
  type = string
  default = "contact@kerocam.com"
}