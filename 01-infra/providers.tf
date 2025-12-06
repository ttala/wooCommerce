terraform {
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
      version = ">= 2.28.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "scaleway" {
  zone   = "pl-waw-1"
  region = "pl-waw"
}