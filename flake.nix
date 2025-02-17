{
  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # using unstable for tofu 1.9.0
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
    ];
  in {
    devShells = supportedSystems (system: {
      default = with nixpkgs.legacyPackages.${system};
        mkShell {
          packages = [
            jq
            yq
            kubectl
            opentofu
            kubernetes-helm
            kubectx
            istioctl
          ];

          shellHook = ''
            echo "Sourcing scripts.sh..."
            if [ -f ./scripts.sh ]; then
              source ./scripts.sh
            else
              echo "Warning: scripts.sh not found!"
            fi
          '';
        };
    });
  };
}
