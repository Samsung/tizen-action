#!/usr/bin/env bash
#
# Check the version of the Tizen Action Compiler.
# Shows the compiler release version, the individual binary versions, and the
# target requirements -- checked against the connected device when there is one.
# Set SDB_SERIAL to pick a device when several are attached.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.action-tools"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Tizen Action Compiler Version ===${NC}\n"

# 1. Compiler version from repository
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
  REPO_VERSION=$(cat "${SCRIPT_DIR}/VERSION")
  echo -e "${GREEN}✓${NC} Repository version: ${REPO_VERSION}"
else
  echo -e "${RED}✗${NC} Repository VERSION file not found"
fi

echo ""

# 2. Installed compiler version
if [[ -f "${INSTALL_DIR}/VERSION" ]]; then
  INSTALLED_VERSION=$(cat "${INSTALL_DIR}/VERSION")
  echo -e "${GREEN}✓${NC} Installed version: ${INSTALLED_VERSION} (at ${INSTALL_DIR})"
else
  echo -e "${YELLOW}⚠${NC}  Compiler not installed yet"
  echo "   Run './install.sh' to install the compiler."
  exit 0
fi

echo ""

# 3. Target (on-device) requirements declared by this release, checked against
#    the connected device when there is exactly one (or SDB_SERIAL picks it).
REQ_FILE=""
for candidate in "${SCRIPT_DIR}/REQUIREMENTS" "${INSTALL_DIR}/REQUIREMENTS"; do
  if [[ -f "${candidate}" ]]; then REQ_FILE="${candidate}"; break; fi
done

SDB_CMD=(sdb)
DEVICE_SKIP=""
if ! command -v sdb >/dev/null 2>&1; then
  DEVICE_SKIP="sdb not found"
elif [[ -n "${SDB_SERIAL:-}" ]]; then
  SDB_CMD=(sdb -s "${SDB_SERIAL}")
else
  DEVICE_COUNT=$(sdb devices 2>/dev/null | tail -n +2 | grep -cw "device" || true)
  if [[ "${DEVICE_COUNT}" -eq 0 ]]; then
    DEVICE_SKIP="no device connected"
  elif [[ "${DEVICE_COUNT}" -gt 1 ]]; then
    DEVICE_SKIP="${DEVICE_COUNT} devices connected, set SDB_SERIAL to choose one"
  fi
fi

# Confirm the target actually answers before reading versions off it; otherwise
# every lookup comes back empty and would be misreported as "not installed".
if [[ -z "${DEVICE_SKIP}" ]] &&
   ! "${SDB_CMD[@]}" shell "true" </dev/null >/dev/null 2>&1; then
  DEVICE_SKIP="device not reachable"
fi

# Echoes -1 / 0 / 1 for a<b / a==b / a>b, ordering version-aware (1.3.9 < 1.3.18).
vercmp() {
  if [[ "$1" == "$2" ]]; then echo 0; return; fi
  if [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; then
    echo -1
  else
    echo 1
  fi
}

# True when "<installed> <op> <wanted>" holds.
version_satisfies() {
  local c
  c=$(vercmp "$1" "$3")
  case "$2" in
    ">=") [[ "${c}" -ge 0 ]] ;;
    ">")  [[ "${c}" -gt 0 ]] ;;
    "="|"==") [[ "${c}" -eq 0 ]] ;;
    "<=") [[ "${c}" -le 0 ]] ;;
    "<")  [[ "${c}" -lt 0 ]] ;;
  esac
}

# Version of an rpm installed on the target; empty when absent or unreadable.
# stdin is closed so sdb cannot swallow the caller's input.
device_version() {
  local out
  out=$("${SDB_CMD[@]}" shell "rpm -q --qf '%{VERSION}' $1" </dev/null 2>/dev/null |
        tr -d '\r' | head -1) || true
  # rpm reports a missing package as prose on stdout, so require a leading digit.
  if [[ "${out}" =~ ^[0-9] ]]; then
    echo "${out}"
  fi
  return 0
}

echo -e "${BLUE}Target requirements:${NC}"
if [[ -z "${REQ_FILE}" ]]; then
  echo -e "  ${YELLOW}⚠${NC}  REQUIREMENTS file not found"
else
  INCOMPATIBLE=0
  while read -r component op wanted _rest; do
    [[ -z "${component}" || "${component}" == \#* ]] && continue

    case "${op}" in
      ">="|">"|"="|"=="|"<="|"<") ;;
      *) echo -e "  ${YELLOW}⚠${NC}  ${component} ${op} ${wanted} (unrecognized constraint)"
         continue ;;
    esac

    if [[ -n "${DEVICE_SKIP}" ]]; then
      echo -e "  • ${component} ${op} ${wanted}"
      continue
    fi

    installed=$(device_version "${component}")
    if [[ -z "${installed}" ]]; then
      echo -e "  ${YELLOW}⚠${NC}  ${component} ${op} ${wanted} (not installed on device)"
    elif version_satisfies "${installed}" "${op}" "${wanted}"; then
      echo -e "  ${GREEN}✓${NC} ${component} ${op} ${wanted} (device: ${installed})"
    else
      echo -e "  ${RED}✗${NC} ${component} ${op} ${wanted} (device: ${installed})"
      INCOMPATIBLE=1
    fi
  done < "${REQ_FILE}"

  if [[ -n "${DEVICE_SKIP}" ]]; then
    echo "  (${DEVICE_SKIP})"
  elif [[ "${INCOMPATIBLE}" -eq 1 ]]; then
    echo -e "  ${RED}Connected device does not meet this compiler's requirements.${NC}"
  fi
fi

echo ""

# 4. Schema data in use: synced from the data repository by actionc-sync. The
#    compiler ships no schemas, so a data dir without DATA_VERSION is a leftover
#    of unknown origin.
DATA_DIR="${ACTIONC_DATA_DIR:-${INSTALL_DIR}/data}"
echo -e "${BLUE}Schema data:${NC}"
if [[ -f "${DATA_DIR}/DATA_VERSION" ]]; then
  echo -e "  ${GREEN}✓${NC} tizen-action $(cat "${DATA_DIR}/DATA_VERSION") (synced from $(cut -d' ' -f1 "${DATA_DIR}/DATA_SOURCE" 2>/dev/null || echo 'the data repository'))"
elif [[ -d "${DATA_DIR}/actions" ]]; then
  echo -e "  ${YELLOW}•${NC} unknown origin, no DATA_VERSION (run 'actionc-sync' to match the device)"
else
  echo -e "  ${RED}✗${NC} no schema data at ${DATA_DIR} (run 'actionc-sync')"
fi

echo ""

# 5. Individual binary versions
echo -e "${BLUE}Binary versions:${NC}"

check_binary() {
  local name="$1"
  local cmd="$2"
  local version_flag="$3"

  if command -v "$cmd" >/dev/null 2>&1; then
    if [[ -n "$version_flag" ]]; then
      # Capture both stdout and stderr; some tools output version to stderr
      # Extract the line starting with the command name
      local version=$($cmd $version_flag 2>&1 | grep "^$cmd" | head -1)
      if [[ -z "$version" ]]; then
        version="installed"
      fi
      echo -e "  ${GREEN}✓${NC} ${name}: ${version}"
    else
      echo -e "  ${GREEN}✓${NC} ${name}: installed"
    fi
  else
    echo -e "  ${RED}✗${NC} ${name}: not found in PATH"
  fi
}

check_binary "actionc" "actionc" "-v"
check_binary "action2tidl" "action2tidl" "--version"
check_binary "tidlc" "tidlc" "-v"

echo ""

# 6. Environment variables
echo -e "${BLUE}Environment variables:${NC}"
echo "  ACTIONC_DATA_DIR=${ACTIONC_DATA_DIR:-${INSTALL_DIR}/data}"
echo "  ACTIONC_ACTION2TIDL=${ACTIONC_ACTION2TIDL:-${INSTALL_DIR}/action2tidl}"
echo "  ACTIONC_TIDLC=${ACTIONC_TIDLC:-${INSTALL_DIR}/tidlc}"

echo ""
echo -e "${GREEN}Done.${NC}"
