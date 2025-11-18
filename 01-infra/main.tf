
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


# Creating LoadBalancer IP
resource "scaleway_lb_ip" "woo_lb_ip" {
  zone = var.zone
}

# Kubeconfig outputs
output "kubeconfig_host" {
  value = scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].host
  sensitive = true
}

output "kubeconfig_token" {
  value = scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].token
  sensitive = true
}

output "kubeconfig_ca" {
  value = scaleway_k8s_cluster.shopsecure_cluster.kubeconfig[0].cluster_ca_certificate
  sensitive = true
}

output "nginx_lb_ip" {
  value = scaleway_lb_ip.woo_lb_ip.ip_address
}

data "scaleway_k8s_cluster" "shopsecure_cluster" {
  depends_on = [scaleway_k8s_pool.full_isolation_pool]
  cluster_id = scaleway_k8s_cluster.shopsecure_cluster.id
}

output "db_host" {
  value = scaleway_rdb_instance.woocommerce_db.endpoint.hostname
}

output "db_port" {
  value = scaleway_rdb_instance.woocommerce_db.endpoint.port
}

output "db_user" {
  value = scaleway_rdb_instance.woocommerce_db.user_name
}

output "db_password" {
  value = scaleway_rdb_instance.woocommerce_db.password
}

output "db_name" {
  value = scaleway_rdb_database.woocommerce.name
}
