data "terraform_remote_state" "infra" {
  backend = "local"

  config = {
    path = "../01-infra/terraform.tfstate"
  }
}


# Providers using Kubeconfig from Infra
provider "kubernetes" {
  host                   = data.terraform_remote_state.infra.outputs.kubeconfig_host
  token                  = data.terraform_remote_state.infra.outputs.kubeconfig_token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.kubeconfig_ca)
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.infra.outputs.kubeconfig_host
    token                  = data.terraform_remote_state.infra.outputs.kubeconfig_token
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.kubeconfig_ca)
  }
}

# Creating LoadBalancer IP
resource "scaleway_lb_ip" "woo_lb_ip" {
  zone = var.zone
}

#Update DNS
#resource "scaleway_domain_record" "woo" {
#  dns_zone = var.domain
#  name     = var.subdomain
#  type     = "A"
#  data     = scaleway_lb_ip.woo_lb_ip.ip_address
#  ttl      = 900
#}

# NGINX Ingress controller
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "kube-system"

  set {
    name  = "controller.service.loadBalancerIP"
    value = scaleway_lb_ip.woo_lb_ip.ip_address
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-proxy-protocol-v2"
    value = "true"
  }

  set {
    name  = "controller.config.use-proxy-protocol"
    value = "true"
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-zone"
    value = var.zone
  }

}

resource "kubernetes_secret" "woocommerce_env" {
  metadata {
    name      = "woocommerce-env"
    namespace = "default"
  }

  data = {
    WORDPRESS_DB_HOST     = data.terraform_remote_state.infra.outputs.db_host
    WORDPRESS_DB_PORT     = data.terraform_remote_state.infra.outputs.db_port
    WORDPRESS_DB_USER     = data.terraform_remote_state.infra.outputs.db_user
    WORDPRESS_DB_PASSWORD = data.terraform_remote_state.infra.outputs.db_password
    WORDPRESS_DB_NAME     = var.db_name
    WORDPRESS_URL         = "${var.subdomain}.${var.domain}"
    WORDPRESS_ADMIN_EMAIL = var.admin_email
  }

  type = "Opaque"
}

output "db_host" {
  value = data.terraform_remote_state.infra.outputs.db_host
}

# Create new storage class
resource "kubernetes_storage_class" "scaleway_immediate" {
  metadata {
    name = "scaleway-immediate"
  }

  storage_provisioner = "csi.scaleway.com"

  volume_binding_mode = "Immediate"

}

# Create Persistent volume claim
resource "kubernetes_persistent_volume_claim" "woocommerce" {
  metadata {
    name = "woocommerce-pvc"
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "scaleway-immediate"
    resources {
      requests = {
        storage = "8Gi"
      }
    }
  }
  depends_on = [
    kubernetes_storage_class.scaleway_immediate
  ]
}

resource "kubernetes_deployment" "woocommerce" {
  metadata {
    name = "woocommerce"
    labels = {
      app = "woocommerce"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "woocommerce"
      }
    }

    template {
      metadata {
        labels = {
          app = "woocommerce"
        }
      }

      spec {
        container {
          name  = "woocommerce"
          image = "rg.fr-par.scw.cloud/ns-woocom/woocommerce:latest"

          port {
            container_port = 80
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.woocommerce_env.metadata[0].name
            }
          }

          volume_mount {
            name       = "woocommerce-data"
            mount_path = "/var/www/html/wp-content"
          }

          # Health checks
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
          }
        }

        volume {
          name = "woocommerce-data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.woocommerce.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "woocommerce" {
  metadata {
    name = "woocommerce"
    labels = {
      app = "woocommerce"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "woocommerce"
    }

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_manifest" "woocommerce_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"

    metadata = {
      name      = "woocommerce"
      namespace = "default"

      annotations = {
        "kubernetes.io/ingress.class" = "nginx"
      }
    }

    spec = {
      rules = [
        {
          host = "${var.subdomain}.${var.domain}"

          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"

                backend = {
                  service = {
                    name = "woocommerce"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}

