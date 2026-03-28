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
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      oddlamaPkgs = import oddlama-nixpkgs { inherit system; };

      baseModule = {
        boot.loader.grub.device = "nodev";
        fileSystems."/" = {
          device = "/dev/sda1";
          fsType = "ext4";
        };
        system.stateVersion = "25.11";
      };

      patchedNixComponents = {
        nix_2_34 = pkgs.nixVersions.nixComponents_2_34.appendPatches [
          ./patches/nix_2_34.patch
        ];
        nix_2_33 = pkgs.nixVersions.nixComponents_2_33.appendPatches [
          ./patches/nix_2_33.patch
        ];
      };

      wrapPatchedNix =
        nixCli:
        pkgs.runCommand "nix-wrapped"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
          }
          ''
            mkdir -p $out/bin
            for bin in ${nixCli}/bin/*; do
              makeWrapper "$bin" "$out/bin/$(basename "$bin")" \
                --suffix NIX_CONFIG $'\n' "extra-experimental-features = dependency-tracking"
            done
          '';
    in
    {
      nixosConfigurations = {
        e2e-base = oddlama-nixpkgs.lib.nixosSystem {
          inherit system;
          trackDependencies = true;
          modules = [ baseModule ];
        };

        e2e-changed = oddlama-nixpkgs.lib.nixosSystem {
          inherit system;
          trackDependencies = true;
          modules = [
            baseModule
            {
              networking.hostName = "tracked-test";
            }
          ];
        };

        benchmark-base = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ baseModule ];
        };

        benchmark-changed = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            baseModule
            {
              networking.hostName = "tracked-test";
            }
          ];
        };
      };

      packages.${system} = {
        nix_2_34 = wrapPatchedNix patchedNixComponents.nix_2_34.nix-cli;
        nix_2_33 = wrapPatchedNix patchedNixComponents.nix_2_33.nix-cli;
        default = wrapPatchedNix patchedNixComponents.nix_2_34.nix-cli;
      };

      apps.${system} =
        let
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

          e2e-check = pkgs.writeShellApplication {
            name = "e2e-check";
            runtimeInputs = [
              oddlamaPkgs.nixos-config
              pkgs.diffutils
            ];
            text = ''
              build_toplevel() {
                local nix_bin="$1"
                local config="$2"

                "$nix_bin" build \
                  --extra-experimental-features 'nix-command flakes' \
                  --print-out-paths \
                  --no-link \
                  "path:${self}#nixosConfigurations.$config.config.system.build.toplevel"
              }

              run_text_diff() {
                local nix_bin="$1"
                local base="$2"
                local changed="$3"
                PATH="$(dirname "$nix_bin"):$PATH" nixos-config text-diff "$base" "$changed" || true
              }

              nix_2_33_bin="${self.packages.x86_64-linux.nix_2_33}/bin/nix"
              nix_2_34_bin="${self.packages.x86_64-linux.nix_2_34}/bin/nix"

              base_2_33="$(build_toplevel "$nix_2_33_bin" e2e-base)"
              changed_2_33="$(build_toplevel "$nix_2_33_bin" e2e-changed)"
              base_2_34="$(build_toplevel "$nix_2_34_bin" e2e-base)"
              changed_2_34="$(build_toplevel "$nix_2_34_bin" e2e-changed)"

              diff_2_33="$(run_text_diff "$nix_2_33_bin" "$base_2_33" "$changed_2_33")"
              diff_2_34="$(run_text_diff "$nix_2_34_bin" "$base_2_34" "$changed_2_34")"

              printf 'nix_2_33 text-diff:\n%s\n' "$diff_2_33"
              printf 'nix_2_34 text-diff:\n%s\n' "$diff_2_34"

              if [[ "$diff_2_33" != "$diff_2_34" ]]; then
                printf '%s\n' "$diff_2_33" > diff-2.33.txt
                printf '%s\n' "$diff_2_34" > diff-2.34.txt
                diff -u diff-2.33.txt diff-2.34.txt
                exit 1
              fi

              expected_diff="$(cat <<'EOF'
                 environment.etc.hostname.text = '''
              -    nixos
              +    tracked-test
                 ''';
              EOF
              )"
              [[ "$diff_2_34" == *"$expected_diff"* ]]

              echo "${oddlamaPkgs.nixos-config}/bin/nixos-config diff \"$base_2_34\" \"$changed_2_34\""
            '';
          };

          benchmark = pkgs.writeShellApplication {
            name = "benchmark";
            runtimeInputs = [ pkgs.hyperfine ];
            text = ''
              set -euo pipefail

              usage() {
                cat <<'EOF'
              Usage: benchmark [VERSION]

              Compare patched and upstream nix on eval and NixOS toplevel build workloads.

              VERSION defaults to 2_34 and must be one of:
                2_34
                2_33

              The benchmark uses upstream-compatible NixOS configurations so the same
              expressions can be evaluated by both binaries.
              EOF
              }

              version="''${1:-2_34}"
              case "$version" in
                2_34)
                  upstream_nix="${pkgs.nixVersions.nixComponents_2_34.nix-cli}/bin/nix"
                  patched_nix="${self.packages.${system}.nix_2_34}/bin/nix"
                  ;;
                2_33)
                  upstream_nix="${pkgs.nixVersions.nixComponents_2_33.nix-cli}/bin/nix"
                  patched_nix="${self.packages.${system}.nix_2_33}/bin/nix"
                  ;;
                -h|--help)
                  usage
                  exit 0
                  ;;
                *)
                  echo "Unknown version: $version" >&2
                  usage >&2
                  exit 1
                  ;;
              esac

              flake_ref="path:${self}"
              experimental_features='nix-command flakes'
              benchmark_attr="nixosConfigurations.benchmark-base.config.system.build.toplevel"
              benchmark_drv_attr="$benchmark_attr.drvPath"

              # Realize both binaries before timing so the benchmark only measures
              # the target workload, not building or fetching the compared nix.
              "$upstream_nix" --version >/dev/null
              "$patched_nix" --version >/dev/null

              make_eval_cmd() {
                local nix_bin="$1"
                local attr="$2"

                printf \
                  '%q --extra-experimental-features %q eval %q --raw >/dev/null' \
                  "$nix_bin" \
                  "$experimental_features" \
                  "$flake_ref#$attr"
              }

              make_build_cmd() {
                local nix_bin="$1"
                local attr="$2"

                printf \
                  '%q --extra-experimental-features %q build %q --no-link >/dev/null' \
                  "$nix_bin" \
                  "$experimental_features" \
                  "$flake_ref#$attr"
              }

              upstream_eval_cmd="$(make_eval_cmd "$upstream_nix" "$benchmark_drv_attr")"
              patched_eval_cmd="$(make_eval_cmd "$patched_nix" "$benchmark_drv_attr")"
              upstream_build_cmd="$(make_build_cmd "$upstream_nix" "$benchmark_attr")"
              patched_build_cmd="$(make_build_cmd "$patched_nix" "$benchmark_attr")"

              hyperfine \
                --warmup 3 \
                --runs 10 \
                --prepare 'sync' \
                --export-markdown "benchmark-$version.md" \
                --export-json "benchmark-$version.json" \
                --command-name "upstream eval drvPath" "$upstream_eval_cmd" \
                --command-name "patched eval drvPath" "$patched_eval_cmd" \
                --command-name "upstream build toplevel --no-link" "$upstream_build_cmd" \
                --command-name "patched build toplevel --no-link" "$patched_build_cmd"
            '';
          };
        in
        {
          diff-svg = {
            type = "app";
            program = "${diff-svg}/bin/diff-svg";
          };

          e2e-check = {
            type = "app";
            program = "${e2e-check}/bin/e2e-check";
          };

          benchmark = {
            type = "app";
            program = "${benchmark}/bin/benchmark";
          };
        };

    };
}
