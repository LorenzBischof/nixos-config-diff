> [!WARNING]
> This repository contains vibecoded content.
> Treat the patches and surrounding packaging as experimental, review everything carefully, and do not assume correctness.

# nixos-config-diff

## Attribution

This repository packages local copies of the Nix evaluator patches used for configuration-level NixOS diffing. The underlying idea, patches, and original implementation come from [oddlama](https://github.com/oddlama):

- Discourse: <https://discourse.nixos.org/t/diffing-nixos-configurations-at-the-config-level/75554>
- Blog post: <https://oddlama.org/blog/tracking-options-in-nixos/>
- Diffing tool: <https://github.com/oddlama/nixos-config-tui>
- Patched `nix`: <https://github.com/oddlama/nix/tree/thunk-origins-v1>
- Patched `nixpkgs`: <https://github.com/oddlama/nixpkgs/tree/thunk-origins-v1>

## Quick Start

The flake provides patched `nix` CLIs for `2.33` and `2.34`, plus helper apps such as `diff-svg`, `e2e-check`, and `benchmark`.

Build the default patched `nix` (`2.34`):

```bash
nix build .#nix_2_34
```

Generate an SVG graph for changes between two tracked toplevels:

```bash
nix run .#diff-svg -- /nix/var/nix/profiles/system-42-link /nix/var/nix/profiles/system-43-link > diff.svg
```

Both toplevels must have been built with `trackDependencies = true`. The included example changes `networking.hostName` in `e2e-changed` relative to `e2e-base`:

![Dependency graph for networking.hostName](diff.svg)

- Red: user-changed options
- Yellow: options that depend on the changed options

## Dependency Tracking

`e2e-base` and `e2e-changed` expose a `dependencyTracking` attrset with counts, config values, dependency edges, and DOT output. Inspect it with the patched `nix`:

```bash
nix run .#nix_2_34 -- eval .#nixosConfigurations.e2e-base.dependencyTracking.counts
nix run .#nix_2_34 -- eval .#nixosConfigurations.e2e-base.dependencyTracking.configValues --json
nix run .#nix_2_34 -- eval .#nixosConfigurations.e2e-base.dependencyTracking.filteredDotOutput --raw > deps.dot
nix run .#nix_2_34 -- build .#nixosConfigurations.e2e-base.config.system.build.toplevel
```

Or open a REPL:

```bash
nix run .#nix_2_34 -- repl .#nixosConfigurations.e2e-base
```

## Checks

```bash
nix run .#e2e-check
```

This builds `e2e-base` and `e2e-changed` with both patched Nix versions and verifies that `nixos-config text-diff` matches across `nix_2_33` and `nix_2_34`.

```bash
nix run .#benchmark
```

Or benchmark a specific version:

```bash
nix run .#benchmark -- 2_34
nix run .#benchmark -- 2_33
```

This compares upstream and patched `nix` on `benchmark-base` for `eval ...drvPath` and `build --no-link ...toplevel`, then writes `benchmark-<version>.md` and `benchmark-<version>.json`.
