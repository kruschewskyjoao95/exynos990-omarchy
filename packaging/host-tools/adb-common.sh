#!/usr/bin/env bash
# Shared host-side helpers for r8s ADB flash and restore scripts.
# Adapted from sources/port/tools/{flash-boot,restore-stock}.sh for GNU/Linux
# portability, explicit single-device selection, and strict backup verification.

adb_require_single_root_device() {
  local devices count
  if [ -n "${ANDROID_SERIAL:-}" ]; then
    adb -s "$ANDROID_SERIAL" get-state >/dev/null 2>&1 || {
      echo "no device matching ANDROID_SERIAL=$ANDROID_SERIAL" >&2
      return 4
    }
  else
    devices=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
    count=$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')
    if [ "$count" -eq 0 ]; then
      echo "no device" >&2
      return 4
    elif [ "$count" -gt 1 ]; then
      echo "multiple ADB devices connected; set ANDROID_SERIAL explicitly" >&2
      return 4
    fi
    ANDROID_SERIAL="$devices"
    export ANDROID_SERIAL
  fi

  if [ "$(adb -s "$ANDROID_SERIAL" shell id -u | tr -d '\r')" != "0" ]; then
    echo "need adb root (adb shell id -u != 0)" >&2
    return 5
  fi
}

adb_cmd() {
  adb -s "$ANDROID_SERIAL" "$@"
}

host_file_size() {
  if stat -c%s "$1" >/dev/null 2>&1; then
    stat -c%s "$1"
  else
    stat -f%z "$1"
  fi
}

host_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

resolve_partition_info() {
  local part=$1
  local dev base sectors
  dev=$(adb_cmd shell "readlink -f /dev/block/by-name/$part" | tr -d '\r')
  [ -n "$dev" ] || { echo "cannot resolve partition '$part'" >&2; return 6; }
  base=$(basename "$dev")
  sectors=$(adb_cmd shell "cat /sys/class/block/$base/size" | tr -d '\r')
  case "$sectors" in
    ''|*[!0-9]*) echo "invalid sector count '$sectors' for $part" >&2; return 6 ;;
  esac
  printf '%s %s %s\n' "$dev" "$sectors" "$((sectors * 512))"
}
