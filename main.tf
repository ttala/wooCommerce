# Creating a private network for cluster isolation
resource "scaleway_vpc_private_network" "woocom_pn" {
    name = "shopsecure-private-net"
    region = var.region
}

# Creating a public gateway for external access
resource "scaleway_vpc_public_gateway" "woocom_gateway" {
    name = "shopsecure-gateway"
    type = "VPC-GW-S"
    zone = var.zone
}

# Attaching the public gateway to the private network
resource "scaleway_vpc_gateway_network" "woocom_gateway_network" {
    gateway_id = scaleway_vpc_public_gateway.woocom_gateway.id
    private_network_id = scaleway_vpc_private_network.woocom_pn.id
    enable_masquerade = true
    zone = var.zone
    ipam_config {
        push_default_route = true
    }
}

# Creating a managed MySQL database for WooCommerce
resource "scaleway_rdb_instance" "woocommerce_db" {
    name = "shopsecure-woocommerce-db"
    node_type = "db-dev-s"
    engine = "MySQL-8"
    is_ha_cluster = true
    user_name = var.db_user
    password = var.db_password
    region = var.region
    private_network {
    pn_id = scaleway_vpc_private_network.woocom_pn.id
    enable_ipam = true
    }
}

# Creating a Kubernetes Kapsule cluster
resource "scaleway_k8s_cluster" "woocom_cluster" {
    name = "shopsecure-kapsule-cluster"
    version = "1.33.4"
    cni = "cilium"
    private_network_id = scaleway_vpc_private_network.woocom_pn.id
    region = var.region
    delete_additional_resources = true
}

# Creating a node pool with full isolation
resource "scaleway_k8s_pool" "full_isolation_pool" {
    cluster_id = scaleway_k8s_cluster.woocom_cluster.id
    name = "full-isolation-pool"
    node_type = "DEV1-M"
    size = 2
    autoscaling = true
    autohealing = true
    min_size = 2
    max_size = 5
    public_ip_disabled = true
    region = var.region
    zone = var.zone
    depends_on = [scaleway_vpc_gateway_network.woocom_gateway_network]
}

data "scaleway_k8s_cluster" "woocom_cluster" {
  depends_on = [scaleway_k8s_pool.full_isolation_pool]
  cluster_id = scaleway_k8s_cluster.woocom_cluster.id
}

provider "kubernetes" {
  host                   = data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].host
  token                  = data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].token
  cluster_ca_certificate = base64decode(
    data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].cluster_ca_certificate
  )
}

provider "kubectl" {
  host                   = data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].host
  token                  = data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].token
  cluster_ca_certificate = base64decode(
    data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].cluster_ca_certificate
  )
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].host
    token                  = data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].token
    cluster_ca_certificate = base64decode(
      data.scaleway_k8s_cluster.woocom_cluster.kubeconfig[0].cluster_ca_certificate
    )
  }
}


# Creating LoadBalancer IP
resource "scaleway_lb_ip" "woo_lb_ip" {
  zone = "pl-waw-1"
}

resource "kubernetes_secret" "woocommerce_env" {
  metadata {
    name = "woocommerce-env"
  }

  data = {
    WORDPRESS_DB_HOST     = scaleway_rdb_instance.woocommerce_db.private_network[0].ip
    WORDPRESS_DB_USER     = var.db_user
    WORDPRESS_DB_PASSWORD = var.db_password
    WORDPRESS_DB_NAME     = "rdb"
    WORDPRESS_URL         = "shoo.kerocam.com"
    WORDPRESS_ADMIN_EMAIL = "contact@kerocam.com"
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
        volume {
          name = "woocommerce-data"
          host_path {
            path = "/data/woocom" 
            type = "DirectoryOrCreate"
          }
        }
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






