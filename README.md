# technikable-zmk-config

ZMK user config for the technikable keyboard. Firmware is built via the
[`zmkfirmware/zmk`](https://github.com/zmkfirmware/zmk) reusable GitHub
Actions workflow (`.github/workflows/build.yml` ->
`zmkfirmware/zmk/.github/workflows/build-user-config.yml@v0.3`), driven by
the board/shield matrix in [`build.yaml`](build.yaml).

## Building locally

`scripts/build.sh` mirrors that GitHub Action locally using Docker, so you
can build and iterate on firmware without pushing to GitHub. It:

1. Reads `build.yaml` to get the same board/shield/snippet/cmake-args matrix
   the Action uses.
2. Runs `west init` / `west update` / `west zephyr-export` inside the same
   `zmkfirmware/zmk-build-arm:stable` container image used in CI (in an
   isolated workspace, since this repo's `zephyr/module.yml` marks it as an
   extra ZMK module, exactly like the CI job does).
3. Runs `west build` for each matrix entry with the same `-DZMK_CONFIG` /
   `-DSHIELD` / `-DZMK_EXTRA_MODULES` args as CI.
4. Copies the resulting `.uf2` (or fallback binary) into `./artifacts/`.

### Requirements

- Docker (daemon running)
- Python 3 (stdlib only, used just to parse `build.yaml`)

### Usage

```sh
# Build every entry in build.yaml -> ./artifacts/*.uf2
./scripts/build.sh

# Force a completely fresh west workspace (like a clean CI checkout)
./scripts/build.sh --clean

# Just refresh West modules/Zephyr export without building firmware
./scripts/build.sh --update-only
```

The first run will take a while (cloning ZMK + Zephyr + toolchain modules).
Subsequent runs reuse the cached workspace in `.west-cache/` and are much
faster, similar to how CI restores its module cache. Both `.west-cache/` and
`artifacts/` are gitignored.

Useful environment overrides (see `scripts/build.sh --help`):

| Variable                | Default                              |
| ------------------------ | ------------------------------------ |
| `ZMK_BUILD_IMAGE`        | `zmkfirmware/zmk-build-arm:stable`   |
| `ZMK_CACHE_DIR`          | `./.west-cache`                      |
| `ZMK_ARTIFACT_DIR`       | `./artifacts`                        |
| `ZMK_BUILD_MATRIX_PATH`  | `build.yaml`                         |
| `ZMK_CONFIG_PATH`        | `config`                             |
| `ZMK_FALLBACK_BINARY`    | `bin`                                |
