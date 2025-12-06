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

# Fetch db password
data "scaleway_secret_version" "db_password" {
  secret_id  = var.db_password_secret_id
  revision    = "1"
}


# Create secret with database info
resource "kubernetes_secret" "woocommerce_env" {
  metadata {
    name      = "woocommerce-env"
    namespace = "default"
  }

  data = {
    WORDPRESS_DB_HOST     = data.terraform_remote_state.infra.outputs.db_host
    WORDPRESS_DB_PORT     = data.terraform_remote_state.infra.outputs.db_port
    WORDPRESS_DB_USER     = data.terraform_remote_state.infra.outputs.db_user
    WORDPRESS_DB_PASSWORD = data.scaleway_secret_version.db_password.data
    WORDPRESS_DB_NAME     = var.db_name
    #WORDPRESS_URL         = "${var.subdomain}.${var.domain}"
    WORDPRESS_ADMIN_EMAIL = var.admin_email
  }

  type = "Opaque"
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
          image = var.docker_image

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

# Creating LoadBalancer IP
resource "scaleway_lb_ip" "woo_lb_ip" {

}

output "woocommerce_lb" {
  value = scaleway_lb_ip.woo_lb_ip.ip_address
}

resource "kubernetes_service" "woocommerce" {
  metadata {
    name = "woocommerce"
    labels = {
      app = "woocommerce"
    }
    annotations = {
    "service.beta.kubernetes.io/scaleway-loadbalancer-protocol" = "http"
  }
  }

  spec {
    type = "LoadBalancer"
    load_balancer_ip = scaleway_lb_ip.woo_lb_ip.ip_address

    selector = {
      app = "woocommerce"
    }

    port {
      port        = 80
      target_port = 80
    }
  }
  depends_on = [
    scaleway_lb_ip.woo_lb_ip
  ]
}
