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

variable "kubeconfig_host" {}
variable "kubeconfig_token" {}
variable "kubeconfig_ca" {}
variable "woo_lb_ip" {}

variable "db_host" {}
variable "db_port" {}
variable "db_user" {}
variable "db_password" {}
variable "db_database" {
  default = "rdb"
}
