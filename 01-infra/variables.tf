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

variable "project_id" {
    type = string
    description = "scaleway project id"
    default = "002c0a6c-bfdb-4714-83b1-d109ffd161ba"
}

variable "db_user" {
    type = string
    description = "username for mysql"
    default = "admin"
}

variable "db_password" {
    type = string
    description = "password for mysql"
    sensitive = true
    default = "Passwd4db1!"
}