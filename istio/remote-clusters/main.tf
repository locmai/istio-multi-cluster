locals {
  istio_namespace = "istio-system"

  # mock host data
  cluster_host = {
    "kind1" = "https://127.0.0.1:8443"
    "kind2" = "https://127.0.0.1:9443"
  }
}

resource "kubernetes_cluster_role" "istio_cluster_reader" {
  for_each = var.clusters
  provider = kubernetes.by_kind[each.key]

  metadata {
    name = "cluster-reader"
  }

  rule {
    api_groups = [
      "config.istio.io",
      "networking.istio.io",
      "rbac.istio.io",
      "security.istio.io",
      "authentication.istio.io",
      "telemetry.istio.io",
      "extensions.istio.io",
    ]
    resources = ["*"]
    verbs     = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources = [
      "pods",
      "services",
      "endpoints",
      "namespaces",
      "secrets",
      "nodes",
      "replicationcontrollers",
    ]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.istio.io"]
    resources  = ["workloadentries"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.x-k8s.io", "gateway.networking.k8s.io"]
    resources  = ["gateways"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["multicluster.x-k8s.io"]
    resources  = ["serviceexports"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  rule {
    api_groups = ["multicluster.x-k8s.io"]
    resources  = ["serviceimports"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["subjectaccessreviews"]
    verbs      = ["create"]
  }
}

resource "kubernetes_service_account" "istio_cluster_reader" {
  for_each = var.clusters
  provider = kubernetes.by_kind[each.key]

  metadata {
    name      = "istio-cluster-reader"
    namespace = local.istio_namespace
  }
}

resource "kubernetes_cluster_role_binding" "istio_cluster_reader" {
  for_each = var.clusters
  provider = kubernetes.by_kind[each.key]

  metadata {
    name = "istio-cluster-reader"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.istio_cluster_reader[each.key].metadata.0.name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.istio_cluster_reader[each.key].metadata.0.name
    namespace = kubernetes_service_account.istio_cluster_reader[each.key].metadata.0.namespace
  }
}

resource "kubernetes_secret" "istio_cluster_reader" {
  for_each = var.clusters
  provider = kubernetes.by_kind[each.key]

  metadata {
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.istio_cluster_reader[each.key].metadata.0.name
    }
    namespace     = local.istio_namespace
    generate_name = "istio-cluster-reader-"
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_secret" "remote_secret" {
  for_each = { for pair in flatten([
    for c1 in var.clusters : [
      for c2 in var.clusters : {
        key   = "${c1}-${c2}"
        value = "${c1}-${c2}"
      } if c1 != c2
    ]
  ]) : pair.key => pair }

  provider = kubernetes.by_kind[split("-", each.key)[0]]

  metadata {
    name      = "istio-remote-secret-${each.key}"
    namespace = local.istio_namespace
    annotations = {
      "networking.istio.io/cluster" = "${each.key}"
    }
    labels = {
      "istio/multiCluster" = "true"
    }
  }

  data = {
    "${each.key}" = <<EOT
apiVersion: v1
kind: Config
current-context: ${each.key}
clusters:
- cluster:
    certificate-authority-data: ${base64encode(kubernetes_secret.istio_cluster_reader[split("-", each.key)[1]].data["ca.crt"])}
  server: ${local.cluster_host[split("-", each.key)[1]]}
  name: ${each.key}
contexts:
- context:
    cluster: ${each.key}
    user: ${each.key}
  name: ${each.key}
users:
- name: ${each.key}
  user:
    token: ${kubernetes_secret.istio_cluster_reader[split("-", each.key)[1]].data["token"]}
preferences: {}
EOT
  }
}

