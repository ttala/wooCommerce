# Woocommerce website deployment on Scaleway using Kubernetes + Terraform
This project provides a production-ready WooCommerce deployment using:

- `Scaleway` (VPC, Kapsule, RDB, Load Balancer, Container registry)
- `Terraform` for infrastructure provisioning
- `Kubernetes` (Kapsule managed cluster)
- `Docker` for WooCommerce container image


The repository is split into two main stages:

- `01-infra/` — Infrastructure provisioning (network, DB, Kapsule cluster)
- `02-k8s/` — Kubernetes deployment (PVC, StorageClass, Deployment, Service LB)