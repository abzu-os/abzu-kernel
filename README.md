# abzu-kernel

Custom Abzu kernel project: XNU 1228 (macOS 10.5.8, ppc RELEASE) rebuilt via Nix.

- `flake.nix` — Nix build for the kernel (includes an in-sandbox NetBSD `config` derivation).
- `.github/workflows/generate-config.yml` — compiles NetBSD `config` and regenerates XNU config files using `scripts/merge.sed` + `scripts/merge.awk`.
- `.github/workflows/build-kernel.yml` — builds the kernel via `nix build` and uploads artifacts.
- `scripts/merge.sed`, `scripts/merge.awk` — the two-stage config-merge pipeline (extracted from upstream XNU `doconf.csh`).

Note: xnu-1228 corresponds to Darwin 9.0.0 / macOS 10.5.8.
