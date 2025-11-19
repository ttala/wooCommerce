# Creating a private network for cluster isolation
resource "scaleway_vpc_private_network" "shopsecure_pn" {
    name = "shopsecure-private-net"
    region = var.region
}

# Creating a public gateway for external access
resource "scaleway_vpc_public_gateway" "shopsecure_gateway" {
    name = "shopsecure-gateway"
    type = "VPC-GW-S"
    zone = var.zone
}

# Attaching the public gateway to the private network
resource "scaleway_vpc_gateway_network" "shopsecure_gateway_network" {
    gateway_id = scaleway_vpc_public_gateway.shopsecure_gateway.id
    private_network_id = scaleway_vpc_private_network.shopsecure_pn.id
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
    pn_id = scaleway_vpc_private_network.shopsecure_pn.id
    enable_ipam = true
    }
}

# Creating a Kubernetes Kapsule cluster
resource "scaleway_k8s_cluster" "shopsecure_cluster" {
    name = "shopsecure-kapsule-cluster"
    version = "1.33.4"
    cni = "cilium"
    private_network_id = scaleway_vpc_private_network.shopsecure_pn.id
    region = var.region
    delete_additional_resources = true
}

# Creating a node pool with full isolation
resource "scaleway_k8s_pool" "full_isolation_pool" {
    cluster_id = scaleway_k8s_cluster.shopsecure_cluster.id
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
    depends_on = [scaleway_vpc_gateway_network.shopsecure_gateway_network]
}

data "scaleway_k8s_cluster" "shopsecure_cluster" {
  depends_on = [scaleway_k8s_pool.full_isolation_pool]
  cluster_id = scaleway_k8s_cluster.shopsecure_cluster.id
}

provider "kubernetes" {
  host                   = data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].host
  token                  = data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].token
  cluster_ca_certificate = base64decode(
    data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].cluster_ca_certificate
  )
}

provider "kubectl" {
  host                   = data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].host
  token                  = data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].token
  cluster_ca_certificate = base64decode(
    data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].cluster_ca_certificate
  )
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].host
    token                  = data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].token
    cluster_ca_certificate = base64decode(
      data.scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].cluster_ca_certificate
    )
  }
}


# Creating LoadBalancer IP
resource "scaleway_lb_ip" "woo_lb_ip" {
  zone = "pl-waw-1"
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.16.1" # <-- pin a version

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "kubectl_manifest" "letsencrypt_prod" {
  depends_on = [helm_release.cert_manager]

  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: contact@kerocam.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
YAML
}


resource "helm_release" "nginx_ingress" {
  name      = "nginx-ingress"
  namespace = "kube-system"

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart = "ingress-nginx"

  set {
    name = "controller.service.loadBalancerIP"
    value = scaleway_lb_ip.woo_lb_ip.ip_address
  }

  // enable proxy protocol to get client ip addr instead of loadbalancer one
  set {
    name = "controller.config.use-proxy-protocol"
    value = "true"
  }
  set {
    name = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-proxy-protocol-v2"
    value = "true"
  }

  // indicates in which zone to create the loadbalancer
  set {
    name = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-zone"
    value = scaleway_lb_ip.woo_lb_ip.zone
  }

  // enable to avoid node forwarding
  set {
    name = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  // enable this annotation to use cert-manager
  //set {
  //  name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-use-hostname"
  //  value = "true"
  //}
}

