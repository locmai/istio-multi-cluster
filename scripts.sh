#!/bin/sh

tools=(kind istioctl kubectl helm kubectx tofu docker)
clusters=(kind1 kind2)

for cluster in "${clusters[@]}"; do
  export "$cluster"="kind-$cluster"
done

run() {
  pre_check;
  create_clusters;
  configure_clusters;
}

pre_check() {
  for bin in "${tools[@]}"; do
    if command -v "$bin" &> /dev/null; then
        test_path=$(command -v "$bin")
        if [[ -x "$test_path" ]]; then
            echo "[✔] $bin is installed and executable at: $test_path"
        else
            echo "[✖] $bin exists but is not executable: $test_path"
        fi
    else
        echo "[✖] $bin is not installed or not in PATH"
    fi
  done

  for cluster in "${clusters[@]}"; do
    config_file="config/${cluster}.kubeconfig"
    if [[ -f "$config_file" ]]; then
        echo "[✔] configuration for $cluster is ready."
    else
        echo "[✖] configuration for $cluster is missing. Run 'create_clusters' to create the clusters."
    fi
  done
}

create_clusters() {
  mkdir -p config
  for cluster in "${clusters[@]}"; do
    kind create cluster --config kind/$cluster-kind.yaml
    kind get kubeconfig --name $cluster >config/$cluster.kubeconfig
    echo "$cluster Kubeconfig generated - config/$cluster.kubeconfig"
  done
}

configure_clusters() {
  init_helm
  for cluster in "${clusters[@]}"; do
    kubectx kind-$cluster
    install_metallb $cluster
    install_spire $cluster
    install_istio $cluster
    install_apps $cluster
    echo "$cluster cluster is configured"
  done
  tofu_apply
}

init_helm() {
  helm repo add istio https://istio-release.storage.googleapis.com/charts
  helm repo add spire https://spiffe.github.io/helm-charts-hardened/
  helm repo update
}

install_metallb() {
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
  while ! is_metallb_pod_ready; do
      echo "metallb controller is not ready yet. Retrying in 5 seconds..."
      sleep 5
  done
  echo "metallb controller is ready"
  kubectl apply -f ./kind/$cluster-metallb.yaml
}

is_metallb_pod_ready() {
    local pod_status
    pod_status=$(kubectl get pods -l component=controller -n metallb-system -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
    
    if [[ "$pod_status" == "True" ]]; then
        return 0  # Pod is ready
    fi
    return 1  # Pod is not ready
}

install_spire() {
  helm upgrade --install -n spire-server spire-crds spire/spire-crds --create-namespace
  kubectl create ns spire-system
  helm upgrade --install -n spire-server spire spire/spire --create-namespace -f ./spire/all-values.yaml -f ./spire/$1-values.yaml
}

install_istio() {
  helm upgrade --install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
  helm upgrade --install --create-namespace istiod istio/istiod -n istio-system -f ./istio/$1-values.yaml --wait
  helm upgrade --install --create-namespace istio-ingress istio/gateway -n istio-ingress --wait
  helm upgrade --install --create-namespace istio-eastwest-gateway istio/gateway -n istio-system -f ./istio/$1-eastwest-gateway-values.yaml --wait
  kubectl apply -f ./istio/all-eastwest-gateway.yaml
  kubectl apply -f ./istio/all-peerauthentication.yaml
  kubectl label namespace default istio-injection=enabled
  echo "istio is ready"
}

install_apps() {
  helm upgrade --install --create-namespace bookinfo ./bookinfo/charts/bookinfo -f ./bookinfo/$1-values.yaml -n default --wait
}

tofu_apply() {
  cd ./istio/remote-clusters
  tofu init
  tofu apply -auto-approve
  cd ../../
}

delete_clusters() {
  for cluster in "${clusters[@]}"; do
    kind delete cluster --name $cluster
    rm -f config/$cluster.kubeconfig
    echo "$cluster deleted"
  done
}
