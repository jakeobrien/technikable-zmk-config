#!/usr/bin/env bash
# Mirrors zmkfirmware/zmk/.github/workflows/build-user-config.yml@v0.3 locally
# using Docker, so you can build firmware without pushing to GitHub.
#
# Reads build.yaml the same way the reusable workflow does, then for each
# entry runs the same west init/update/zephyr-export/build sequence inside
# the same zmkfirmware/zmk-build-arm:stable container image used in CI.
#
# Usage:
#   scripts/build.sh                 Build every entry in build.yaml
#   scripts/build.sh --clean         Wipe the cached west workspace first
#   scripts/build.sh --update-only   Only do west init/update/zephyr-export
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE="${ZMK_BUILD_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
CACHE_DIR="${ZMK_CACHE_DIR:-$REPO_ROOT/.west-cache}"
ARTIFACT_DIR="${ZMK_ARTIFACT_DIR:-$REPO_ROOT/artifacts}"
BUILD_MATRIX_PATH="${ZMK_BUILD_MATRIX_PATH:-build.yaml}"
CONFIG_PATH="${ZMK_CONFIG_PATH:-config}"
FALLBACK_BINARY="${ZMK_FALLBACK_BINARY:-bin}"

CLEAN=0
UPDATE_ONLY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Mirrors the zmkfirmware/zmk build-user-config.yml GitHub Action locally
using Docker + the zmkfirmware/zmk-build-arm:stable image.

Options:
  -c, --clean         Remove the cached west workspace first (forces a fresh
                       'west init' + 'west update', like a fresh CI checkout)
  -u, --update-only   Only run west init/update/zephyr-export, skip building
  -h, --help          Show this help

Environment overrides:
  ZMK_BUILD_IMAGE        Docker image to use (default: zmkfirmware/zmk-build-arm:stable)
  ZMK_CACHE_DIR           Persistent west workspace dir (default: ./.west-cache)
  ZMK_ARTIFACT_DIR        Where built firmware is copied (default: ./artifacts)
  ZMK_BUILD_MATRIX_PATH   Path to the build matrix file (default: build.yaml)
  ZMK_CONFIG_PATH         Path to the config dir (default: config)
  ZMK_FALLBACK_BINARY     Fallback binary extension if no .uf2 is built (default: bin)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--clean) CLEAN=1 ;;
    -u|--update-only) UPDATE_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is required but was not found in PATH" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required but was not found in PATH" >&2
  exit 1
fi

if [ "$CLEAN" -eq 1 ]; then
  echo "==> Removing cached west workspace at $CACHE_DIR"
  rm -rf "$CACHE_DIR"
fi

mkdir -p "$CACHE_DIR" "$ARTIFACT_DIR"

MATRIX_FILE="$(mktemp)"
trap 'rm -f "$MATRIX_FILE"' EXIT
python3 "$REPO_ROOT/scripts/gen_matrix.py" "$REPO_ROOT/$BUILD_MATRIX_PATH" > "$MATRIX_FILE"

if [ ! -s "$MATRIX_FILE" ] && [ "$UPDATE_ONLY" -eq 0 ]; then
  echo "error: no entries found in $BUILD_MATRIX_PATH" >&2
  exit 1
fi

if [ -s "$MATRIX_FILE" ]; then
  echo "==> Build matrix (board, shield, snippet, cmake-args, artifact-name):"
  cat "$MATRIX_FILE"
fi

# The upstream action special-cases repos that are themselves a zephyr
# module (extra board/shield definitions living alongside `config/`, as
# indicated by a zephyr/module.yml file) by passing the checkout in as an
# extra ZMK module. Mirror that check here.
EXTRA_MODULE_ARG=""
if [ -f "$REPO_ROOT/zephyr/module.yml" ]; then
  EXTRA_MODULE_ARG="-DZMK_EXTRA_MODULES=/workspace"
fi

docker run --rm \
  -v "$REPO_ROOT:/workspace:ro" \
  -v "$CACHE_DIR:/zmk-workspace" \
  -v "$MATRIX_FILE:/tmp/matrix.tsv:ro" \
  -v "$ARTIFACT_DIR:/artifacts" \
  -e "EXTRA_MODULE_ARG=$EXTRA_MODULE_ARG" \
  -e "CONFIG_PATH=$CONFIG_PATH" \
  -e "FALLBACK_BINARY=$FALLBACK_BINARY" \
  -e "UPDATE_ONLY=$UPDATE_ONLY" \
  "$IMAGE" \
  bash /workspace/scripts/in-container-build.sh

echo ""
echo "==> Done. Firmware written to: $ARTIFACT_DIR"
ls -la "$ARTIFACT_DIR"
