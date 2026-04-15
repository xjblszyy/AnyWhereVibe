#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

sdk_root="${MRT_ANDROID_SDK_ROOT:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/share/android-commandlinetools}}}"
android_dir="${repo_root}/android"
gradle_cmd="${android_dir}/gradlew"
avd_name="${MRT_ANDROID_AVD_NAME:-mrtApi35}"
device_profile="${MRT_ANDROID_DEVICE_PROFILE:-pixel_8}"
host_arch="$(uname -m)"
system_image="${MRT_ANDROID_SYSTEM_IMAGE:-}"
adb_bin="${sdk_root}/platform-tools/adb"
emulator_bin="${sdk_root}/emulator/emulator"
sdkmanager_bin="${sdk_root}/cmdline-tools/latest/bin/sdkmanager"
avdmanager_bin="${sdk_root}/cmdline-tools/latest/bin/avdmanager"
emulator_log="${TMPDIR:-/tmp}/mrt-android-emulator.log"
started_emulator="false"
emulator_serial=""
original_local_properties=""
had_local_properties="false"

require_file() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    echo "error: required file '${path}' was not found." >&2
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: required command '${cmd}' was not found in PATH." >&2
    exit 1
  fi
}

resolve_system_image() {
  if [[ -n "${system_image}" ]]; then
    echo "${system_image}"
    return 0
  fi

  local installed_arm64="system-images;android-35;google_atd;arm64-v8a"
  local installed_x86_64="system-images;android-35;google_atd;x86_64"
  if [[ -d "${sdk_root}/$(sdk_path_for_package "${installed_arm64}")" ]]; then
    echo "${installed_arm64}"
    return 0
  fi
  if [[ -d "${sdk_root}/$(sdk_path_for_package "${installed_x86_64}")" ]]; then
    echo "${installed_x86_64}"
    return 0
  fi

  case "${host_arch}" in
    arm64|aarch64)
      echo "${installed_arm64}"
      ;;
    x86_64|amd64)
      echo "${installed_x86_64}"
      ;;
    *)
      echo "error: unsupported host architecture '${host_arch}'. Set MRT_ANDROID_SYSTEM_IMAGE explicitly." >&2
      exit 1
      ;;
  esac
}

sdk_path_for_package() {
  local package="$1"
  printf '%s' "${package//;/\/}"
}

cleanup() {
  if [[ "${started_emulator}" == "true" && -n "${emulator_serial}" ]]; then
    "${adb_bin}" -s "${emulator_serial}" emu kill >/dev/null 2>&1 || true
  fi

  if [[ "${had_local_properties}" == "true" ]]; then
    printf "%s" "${original_local_properties}" > "${android_dir}/local.properties"
  else
    rm -f "${android_dir}/local.properties"
  fi
}
trap cleanup EXIT

require_cmd uname
require_file "${gradle_cmd}"
require_file "${adb_bin}"
require_file "${sdkmanager_bin}"
require_file "${avdmanager_bin}"

if [[ -x "${emulator_bin}" ]]; then
  true
else
  echo "info: Android emulator binary not found, installing emulator package..." >&2
  yes | "${sdkmanager_bin}" --sdk_root="${sdk_root}" "emulator" >/dev/null
fi

system_image="$(resolve_system_image)"
if [[ ! -d "${sdk_root}/$(sdk_path_for_package "${system_image}")" ]]; then
  echo "info: Installing Android system image '${system_image}'..." >&2
  yes | "${sdkmanager_bin}" --sdk_root="${sdk_root}" "${system_image}" >/dev/null
fi

if [[ -f "${android_dir}/local.properties" ]]; then
  had_local_properties="true"
  original_local_properties="$(cat "${android_dir}/local.properties")"
fi
printf "sdk.dir=%s\n" "${sdk_root}" > "${android_dir}/local.properties"

if [[ ! -d "${HOME}/.android/avd/${avd_name}.avd" ]]; then
  echo "info: Creating AVD '${avd_name}'..." >&2
  printf 'no\n' | "${avdmanager_bin}" create avd -n "${avd_name}" -k "${system_image}" -d "${device_profile}" >/dev/null
fi

existing_emulator="$("${adb_bin}" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1; exit}')"
existing_avd_process="$(pgrep -f "qemu-system-.* -avd ${avd_name}|emulator.*-avd ${avd_name}" | head -n 1 || true)"
if [[ -n "${existing_emulator}" ]]; then
  emulator_serial="${existing_emulator}"
  echo "info: Reusing running emulator '${emulator_serial}'." >&2
elif [[ -n "${existing_avd_process}" ]]; then
  echo "info: Found existing emulator process for AVD '${avd_name}', waiting for adb device..." >&2
  deadline=$((SECONDS + 120))
  while (( SECONDS < deadline )); do
    emulator_serial="$("${adb_bin}" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1; exit}')"
    if [[ -n "${emulator_serial}" ]]; then
      break
    fi
    sleep 2
  done

  if [[ -z "${emulator_serial}" ]]; then
    echo "error: existing emulator process for '${avd_name}' did not expose an adb device in time." >&2
    exit 1
  fi
else
  echo "info: Starting emulator '${avd_name}'..." >&2
  nohup "${emulator_bin}" \
    -avd "${avd_name}" \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -gpu swiftshader_indirect \
    -no-snapshot > "${emulator_log}" 2>&1 &
  started_emulator="true"

  deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    emulator_serial="$("${adb_bin}" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1; exit}')"
    if [[ -n "${emulator_serial}" ]]; then
      break
    fi
    sleep 2
  done

  if [[ -z "${emulator_serial}" ]]; then
    echo "error: timed out waiting for emulator device to appear." >&2
    if [[ -f "${emulator_log}" ]]; then
      cat "${emulator_log}" >&2
    fi
    exit 1
  fi
fi

echo "info: Waiting for emulator '${emulator_serial}' boot completion..." >&2
"${adb_bin}" -s "${emulator_serial}" wait-for-device >/dev/null
deadline=$((SECONDS + 240))
while (( SECONDS < deadline )); do
  if [[ "$("${adb_bin}" -s "${emulator_serial}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 2
done

if [[ "$("${adb_bin}" -s "${emulator_serial}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; then
  echo "error: emulator '${emulator_serial}' did not finish booting in time." >&2
  if [[ -f "${emulator_log}" ]]; then
    cat "${emulator_log}" >&2
  fi
  exit 1
fi

echo "info: Running Android instrumentation tests on '${emulator_serial}'..." >&2
(
  cd "${android_dir}"
  chmod +x "${gradle_cmd}"
  ./gradlew :app:connectedDebugAndroidTest
)
