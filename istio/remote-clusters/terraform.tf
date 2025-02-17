provider "kubernetes" {
  alias       = "by_kind"
  for_each    = var.clusters
  config_path = "../../config/${each.key}.kubeconfig"
}

