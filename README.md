> [!WARNING]
> This repository contains vibecoded content.
> Treat the patches and surrounding packaging as experimental, review everything carefully, and do not assume correctness.

# nixos-config-diff

## Attribution

This repository builds on work by [oddlama](https://github.com/oddlama).
The underlying idea and original implementation come from oddlama's work.

Relevant upstream context:

- Discourse announcement: <https://discourse.nixos.org/t/diffing-nixos-configurations-at-the-config-level/75554>
- Blog post: <https://oddlama.org/blog/tracking-options-in-nixos/>
- Diffing tool: <https://github.com/oddlama/nixos-config-tui>
- Patched `nix` branch: <https://github.com/oddlama/nix/tree/thunk-origins-v1>
- Patched `nixpkgs` branch: <https://github.com/oddlama/nixpkgs/tree/thunk-origins-v1>


This repository packages local copies of the Nix evaluator patches used for configuration-level NixOS diffing.

The patches in [`patches/`](./patches) are derived from oddlama's work on tracking NixOS option values and dependencies, and are exposed here as a small flake that builds patched `nix` CLI packages for Nix `2.33` and `2.34`.

## Packages

This flake provides:

- `.#nix_2_33`
- `.#nix_2_34`
- `.#default` (`nix_2_34`)

Build one with:

```bash
nix build .#nix_2_34
```

## E2E Check

Run the end-to-end diff check with:

```bash
nix run .#e2e-check
```
