
# Providers using Kubeconfig from Infra
provider "kubernetes" {
  host                   = var.kubeconfig_host
  token                  = var.kubeconfig_token
  cluster_ca_certificate = base64decode(var.kubeconfig_ca)
}

provider "helm" {
  kubernetes {
    host                   = var.kubeconfig_host
    token                  = var.kubeconfig_token
    cluster_ca_certificate = base64decode(var.kubeconfig_ca)
  }
}


# NGINX Ingress controller
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "kube-system"

  set {
    name  = "controller.service.loadBalancerIP"
    value = var.woo_lb_ip
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

module "mysql" {
  source = "../01-infra/main"
}

module "woocommerce" {
  source   = "../modules/woocommerce"

  db_host     = module.mysql.db_host
  db_port     = module.mysql.db_port
  db_user     = module.mysql.db_user
  db_password = module.mysql.db_password
  db_name     = module.mysql.db_name
}

resource "kubernetes_secret" "woocommerce_env" {
  metadata {
    name      = "woocommerce-env"
    namespace = "default"
  }

  data = {
    DB_HOST     = base64encode(var.db_host)
    DB_PORT     = base64encode(var.db_port)
    DB_USER     = base64encode(var.db_user)
    DB_PASSWORD = base64encode(var.db_password)
    DB_NAME     = base64encode(var.db_name)
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "woocommerce" {
  metadata {
    name = "woocommerce-pvc"
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "woocommerce" {
  metadata {
    name = "woocommerce"
    labels = {
      app = "woocommerce"
    }
  }

  spec {
    replicas = 2

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
          host = "woo.kerocam.com"

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

