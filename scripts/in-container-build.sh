#!/usr/bin/env bash
# Runs *inside* the zmkfirmware/zmk-build-arm container. Mirrors the steps of
# zmkfirmware/zmk/.github/workflows/build-user-config.yml.
set -euo pipefail

CONFIG_PATH="${CONFIG_PATH:-config}"
FALLBACK_BINARY="${FALLBACK_BINARY:-bin}"
WEST_WORKSPACE="/zmk-workspace"

cd "$WEST_WORKSPACE"

echo "==> Syncing ${CONFIG_PATH}/ into isolated west workspace"
rm -rf "$CONFIG_PATH"
mkdir -p "$CONFIG_PATH"
cp -R "/workspace/${CONFIG_PATH}/." "$CONFIG_PATH/"

if [ ! -d .west ]; then
  echo "==> west init"
  west init -l "$CONFIG_PATH"
fi

echo "==> west update"
west update --fetch-opt=--filter=tree:0

echo "==> west zephyr-export"
west zephyr-export

if [ "${UPDATE_ONLY:-0}" = "1" ]; then
  echo "==> --update-only requested, skipping firmware build"
  exit 0
fi

mkdir -p /artifacts

built_any=0
while IFS=$'\t' read -r board shield snippet cmake_args artifact_name; do
  [ -z "$board" ] && continue
  built_any=1

  display_name="${shield:+$shield - }${board}"
  name="${artifact_name:-${shield:+$shield-}${board}-zmk}"
  build_dir="/tmp/build-${name}"

  extra_west_args=()
  [ -n "$snippet" ] && extra_west_args+=(-S "$snippet")

  extra_cmake_args=()
  [ -n "$shield" ] && extra_cmake_args+=(-DSHIELD="$shield")
  [ -n "${EXTRA_MODULE_ARG:-}" ] && extra_cmake_args+=("$EXTRA_MODULE_ARG")
  if [ -n "$cmake_args" ]; then
    # Matches the CI behaviour of splatting `matrix.cmake-args` unquoted.
    # shellcheck disable=SC2206
    extra_cmake_args+=($cmake_args)
  fi

  echo ""
  echo "==> Building ${display_name} -> artifacts/${name}"
  rm -rf "$build_dir"
  west build -s zmk/app -d "$build_dir" -b "$board" \
    "${extra_west_args[@]}" \
    -- -DZMK_CONFIG="${WEST_WORKSPACE}/${CONFIG_PATH}" "${extra_cmake_args[@]}"

  if [ -f "${build_dir}/zephyr/zmk.uf2" ]; then
    cp "${build_dir}/zephyr/zmk.uf2" "/artifacts/${name}.uf2"
    echo "==> Wrote artifacts/${name}.uf2"
  elif [ -f "${build_dir}/zephyr/zmk.${FALLBACK_BINARY}" ]; then
    cp "${build_dir}/zephyr/zmk.${FALLBACK_BINARY}" "/artifacts/${name}.${FALLBACK_BINARY}"
    echo "==> Wrote artifacts/${name}.${FALLBACK_BINARY}"
  else
    echo "!! No firmware output found for ${display_name}" >&2
    exit 1
  fi
done < /tmp/matrix.tsv

if [ "$built_any" -eq 0 ]; then
  echo "No build matrix entries to build" >&2
  exit 1
fi
