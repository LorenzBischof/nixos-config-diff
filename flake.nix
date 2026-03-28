{
  description = "Nix with thunk-origins patches for config diffing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    oddlama-nixpkgs.url = "github:oddlama/nixpkgs/thunk-origins-v1";
  };

  outputs =
    {
      self,
      nixpkgs,
      oddlama-nixpkgs,
    }:
    {
      nixosConfigurations = {
        e2e-base = oddlama-nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          trackDependencies = true;
          modules = [
            {
              boot.loader.grub.device = "nodev";
              fileSystems."/" = {
                device = "/dev/sda1";
                fsType = "ext4";
              };
              system.stateVersion = "25.11";
            }
          ];
        };

        e2e-changed = oddlama-nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          trackDependencies = true;
          modules = [
            {
              boot.loader.grub.device = "nodev";
              fileSystems."/" = {
                device = "/dev/sda1";
                fsType = "ext4";
              };
              system.stateVersion = "25.11";
              networking.hostName = "tracked-test";
            }
          ];
        };
      };

      packages.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          nix_2_34 = pkgs.nixVersions.nixComponents_2_34.appendPatches [
            ./patches/nix_2_34.patch
          ];
          nix_2_33 = pkgs.nixVersions.nixComponents_2_33.appendPatches [
            ./patches/nix_2_33.patch
          ];
        in
        {
          nix_2_34 = nix_2_34.nix-cli;
          nix_2_33 = nix_2_33.nix-cli;
          default = nix_2_34.nix-cli;
        };

      apps.x86_64-linux.diff-svg =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          diff-svg = pkgs.writeShellApplication {
            name = "diff-svg";
            runtimeInputs = [
              pkgs.python3
              pkgs.graphviz
            ];
            text = ''
              if [ "$#" -ne 2 ]; then
                echo "Usage: diff-svg BASE_TOPLEVEL CHANGED_TOPLEVEL" >&2
                echo "Example: diff-svg /nix/var/nix/profiles/system-42-link /nix/var/nix/profiles/system-43-link" >&2
                exit 1
              fi
              exec python3 ${./diff-svg.py} "$1" "$2"
            '';
          };
        in
        {
          type = "app";
          program = "${diff-svg}/bin/diff-svg";
        };

      apps.x86_64-linux.e2e-check =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          oddlamaPkgs = import oddlama-nixpkgs { system = "x86_64-linux"; };
          e2e-check = pkgs.writeShellApplication {
            name = "e2e-check";
            runtimeInputs = [
              self.packages.x86_64-linux.nix_2_34
              oddlamaPkgs.nixos-config
              pkgs.jq
            ];
            text = ''
              build_toplevel() {
                local config="$1"

                nix build \
                  --extra-experimental-features 'nix-command flakes' \
                  --print-out-paths \
                  --no-link \
                  "path:${self}#nixosConfigurations.$config.config.system.build.toplevel"
              }

              base="$(build_toplevel e2e-base)"
              changed="$(build_toplevel e2e-changed)"

              diff_text="$(nixos-config text-diff "$base" "$changed" || true)"
              printf '%s\n' "$diff_text"

              expected_diff="$(cat <<'EOF'
                 environment.etc.hostname.text = '''
              -    nixos
              +    tracked-test
                 ''';
              EOF
              )"
              [[ "$diff_text" == *"$expected_diff"* ]]

              echo "${oddlamaPkgs.nixos-config}/bin/nixos-config diff \"$base\" \"$changed\""
            '';
          };
        in
        {
          type = "app";
          program = "${e2e-check}/bin/e2e-check";
        };
    };
}
