terraform {
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
      version = ">= 2.28.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.23.0"
    }

    helm = {
        source  = "hashicorp/helm"
        version = "2.11.0"
    }
  }
  required_version = ">= 1.5.0"
}