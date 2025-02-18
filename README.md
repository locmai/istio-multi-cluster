## Prerequisites

- [Nix](https://nixos.org/download.html)
- [Docker](https://docs.docker.com/get-docker/)

## Getting started

To start a bash shell that provides an interactive build environment:

```
nix develop
```


Run the prerequisites-check:

```
pre_check
[✔] kind is installed and executable at: /run/current-system/sw/bin/kind
[✔] istioctl is installed and executable at: /nix/store/ysssjrr2bf7hprszqmgqbw8f4rp291y9-istioctl-1.24.3/bin/istioctl
[✔] kubectl is installed and executable at: /nix/store/fdg47848h1jm48dvq34vzjx7pxipipyj-kubectl-1.32.2/bin/kubectl
[✔] helm is installed and executable at: /nix/store/vw1p06zqaj6f24qqiajy9cvzbignldj9-kubernetes-helm-3.17.1/bin/helm
[✔] kubectx is installed and executable at: /nix/store/4i1g0ihxw4hpw0cj6grsk2xgqma3nzfq-kubectx-0.9.5/bin/kubectx
[✔] tofu is installed and executable at: /nix/store/bk8lbpai9gckl24971cd7sy86nx65vqp-opentofu-1.9.0/bin/tofu
[✔] docker is installed and executable at: /run/current-system/sw/bin/docker
[✖] Configuration for kind1 is missing. Run 'creae_clusters' to create the clusters.
[✖] Configuration for kind2 is missing. Run 'creae_clusters' to create the clusters.
```


To build the clusters and configure them, run the following commands in the nix shell:

```
# Create the kind clusters
create_clusters

# Configure the clusters with Istio
configure_clusters

# Run tofu apply to setup remote secrets
tofu_apply
```

