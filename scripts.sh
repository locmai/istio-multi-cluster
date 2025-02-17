#!/bin/sh

tools=(kind istioctl kubectl helm kubectx tofu)
clusters=(kind1 kind2)

for cluster in "${clusters[@]}"; do
  export "$cluster"="kind-$cluster"
done

init() {
  echo "Pre-check"
  pre_check;
  echo "Setup Helm"
  init_helm
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
        echo "[✔] Configuration for $cluster is ready."
    else
        echo "[✖] Configuration for $cluster is missing. Run 'creae_clusters' to create the clusters."
    fi
  done
}

create_clusters() {
  for cluster in "${clusters[@]}"; do
    kind create cluster --config kind/$cluster-kind.yaml
    kind get kubeconfig --name $cluster >config/$cluster.kubeconfig
    echo "$cluster Kubeconfig generated - config/$cluster.kubeconfig"
  done
}

configure_clusters() {
  for cluster in "${clusters[@]}"; do
    kubectx kind-$cluster
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
    echo "Waiting for metallb controller to be ready..."
    while ! is_pod_ready; do
        echo "metallb controller is not ready yet. Retrying in 5 seconds..."
        sleep 5
    done
    echo "metallb controller is ready"
    kubectl apply -f ./kind/$cluster-metallb.yaml
    helm upgrade --install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
    helm upgrade --install --create-namespace istiod istio/istiod -n istio-system -f ./istio/$cluster-values.yaml --wait
    helm upgrade --install --create-namespace istio-ingress istio/gateway -n istio-ingress --wait
    kubectl apply -f ./istio/eastwest-gateway.yaml 
    kubectl label namespace default istio-injection=enabled
    helm upgrade --install --create-namespace bookinfo ./bookinfo/charts/bookinfo -f ./bookinfo/$cluster-values.yaml -n default --wait
    echo "$cluster configured"
  done
}

delete_clusters() {
  for cluster in "${clusters[@]}"; do
    kind delete cluster --name $cluster
    rm -f config/$cluster.kubeconfig
    echo "$cluster deleted"
  done
}

init_helm() {
  helm repo add istio https://istio-release.storage.googleapis.com/charts
  helm repo update
}

LABEL_SELECTOR="component=controller"
NAMESPACE="metallb-system"

is_pod_ready() {
    local pod_status
    pod_status=$(kubectl get pods -l $LABEL_SELECTOR -n $NAMESPACE -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
    
    if [[ "$pod_status" == "True" ]]; then
        return 0  # Pod is ready
    fi
    return 1  # Pod is not ready
}

tofu_apply() {
  cd ./istio/remote-clusters
  tofu init
  tofu apply -auto-approve
  cd ../../
}
