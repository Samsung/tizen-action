#!/usr/bin/env bash
#
# Sync the Tizen Action Compiler schema data (actions/, entities/, action.seq)
# with the tizen-action version installed on the attached device.
#
# The compiler binaries (actionc, action2tidl, tidlc) are reused as installed;
# only the schema data is fetched, from the git repository named in
# data-repo.conf, and installed into ~/.action-tools/data where actionc reads it.
#
# Usage: actionc-sync [options]
#   -t, --target VERSION   sync to this tizen-action version instead of the one
#                          in data-repo.conf (DATA_VERSION) or on the device
#   -l, --list             list the versions available in the data repository
#   -d, --data-dir DIR     install the schemas into DIR instead of
#                          ~/.action-tools/data
#   -o, --offline          do not contact the repository; reuse the last fetch
#   -q, --quiet            only print warnings and errors
#   -h, --help             show this help
#
# Environment:
#   SDB_SERIAL                device to query when several are attached
#   ACTIONC_DATA_REPO         overrides DATA_REPO in data-repo.conf
#   ACTIONC_DATA_REPO_BRANCH  overrides DATA_REPO_BRANCH in data-repo.conf
#   ACTIONC_DATA_VERSION      overrides DATA_VERSION in data-repo.conf
#
# The version to sync to is taken from, in order: --target, ACTIONC_DATA_VERSION,
# DATA_VERSION in data-repo.conf, and finally the attached device over sdb.
#
# Version matching: the directory named exactly like the device version is
# used when it exists; otherwise the highest version with the same
# <major>.<minor> that is not newer than the device.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.action-tools"
CACHE_DIR="${INSTALL_DIR}/data-repo"

TARGET=""
LIST_ONLY=0
DATA_DIR="${INSTALL_DIR}/data"
DATA_DIR_SET=0
OFFLINE=0
QUIET=0

usage() { awk 'NR > 2 && !/^#/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)   TARGET="${2:-}"; shift 2 ;;
    -l|--list)     LIST_ONLY=1; shift ;;
    -d|--data-dir) DATA_DIR="${2:-}"; DATA_DIR_SET=1; shift 2 ;;
    -o|--offline)  OFFLINE=1; shift ;;
    -q|--quiet)    QUIET=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log()  { [[ "${QUIET}" -eq 1 ]] || echo "$@"; }
warn() { echo "warning: $*" >&2; }
die()  { echo "error: $*" >&2; exit 1; }

# --- Configuration -------------------------------------------------------
# The installed conf wins; the one next to this script covers running from the
# repository checkout before install.
CONF_FILE=""
for candidate in "${INSTALL_DIR}/data-repo.conf" "${SCRIPT_DIR}/data-repo.conf"; do
  if [[ -f "${candidate}" ]]; then CONF_FILE="${candidate}"; break; fi
done

DATA_REPO=""
DATA_REPO_BRANCH="main"
DATA_VERSION=""
if [[ -n "${CONF_FILE}" ]]; then
  while IFS='=' read -r key value; do
    key="${key//[[:space:]]/}"
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "${key}" in
      DATA_REPO)        DATA_REPO="${value}" ;;
      DATA_REPO_BRANCH) DATA_REPO_BRANCH="${value}" ;;
      DATA_VERSION)     DATA_VERSION="${value}" ;;
    esac
  done < "${CONF_FILE}"
fi
DATA_REPO="${ACTIONC_DATA_REPO:-${DATA_REPO}}"
DATA_REPO_BRANCH="${ACTIONC_DATA_REPO_BRANCH:-${DATA_REPO_BRANCH}}"
DATA_VERSION_SOURCE="${CONF_FILE}"
if [[ -n "${ACTIONC_DATA_VERSION:-}" ]]; then
  DATA_VERSION="${ACTIONC_DATA_VERSION}"
  DATA_VERSION_SOURCE="ACTIONC_DATA_VERSION"
fi
[[ "${DATA_VERSION}" == "auto" ]] && DATA_VERSION=""
[[ -n "${DATA_REPO}" ]] || die "no data repository configured (DATA_REPO in data-repo.conf or ACTIONC_DATA_REPO)"

command -v git >/dev/null 2>&1 || die "git is required to fetch the schema data"

# --- Fetch the data repository -------------------------------------------
# A shallow clone of the configured branch is kept in ${CACHE_DIR} and
# fast-forwarded on every run; a changed URL or branch starts it over.
fetch_repo() {
  if [[ -d "${CACHE_DIR}/.git" ]]; then
    local have_url have_branch
    have_url=$(git -C "${CACHE_DIR}" config --get remote.origin.url 2>/dev/null || true)
    have_branch=$(git -C "${CACHE_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [[ "${have_url}" != "${DATA_REPO}" || "${have_branch}" != "${DATA_REPO_BRANCH}" ]]; then
      log "Data repository changed; re-fetching."
      rm -rf "${CACHE_DIR}"
    fi
  fi

  if [[ "${OFFLINE}" -eq 1 ]]; then
    [[ -d "${CACHE_DIR}/.git" ]] || die "no previously fetched data to use offline"
    log "Offline: using data fetched $(git -C "${CACHE_DIR}" log -1 --format=%cd --date=short 2>/dev/null || echo earlier)."
    return
  fi

  mkdir -p "${INSTALL_DIR}"
  if [[ -d "${CACHE_DIR}/.git" ]]; then
    log "Fetching ${DATA_REPO} (${DATA_REPO_BRANCH})..."
    if git -C "${CACHE_DIR}" fetch --quiet --depth 1 origin "${DATA_REPO_BRANCH}" </dev/null; then
      git -C "${CACHE_DIR}" checkout --quiet -B "${DATA_REPO_BRANCH}" FETCH_HEAD
    else
      warn "fetch failed; using data fetched $(git -C "${CACHE_DIR}" log -1 --format=%cd --date=short 2>/dev/null || echo earlier)."
    fi
  else
    log "Cloning ${DATA_REPO} (${DATA_REPO_BRANCH})..."
    git clone --quiet --depth 1 --branch "${DATA_REPO_BRANCH}" "${DATA_REPO}" "${CACHE_DIR}" </dev/null ||
      die "could not clone ${DATA_REPO}. Check network access and credentials, or set ACTIONC_DATA_REPO."
  fi
}

# Versions published in the repository, one per line, oldest first.
available_versions() {
  local d
  for d in "${CACHE_DIR}"/*/; do
    d="${d%/}"; d="${d##*/}"
    if [[ "${d}" =~ ^[0-9]+(\.[0-9]+)+$ && -d "${CACHE_DIR}/${d}/actions" ]]; then
      echo "${d}"
    fi
  done | sort -V
}

fetch_repo

if [[ "${LIST_ONLY}" -eq 1 ]]; then
  echo "Schema data versions in ${DATA_REPO} (${DATA_REPO_BRANCH}):"
  available_versions | sed 's/^/  /'
  exit 0
fi

# --- Target version (option, then conf/env, then the device over sdb) -----
if [[ -z "${TARGET}" && -n "${DATA_VERSION}" ]]; then
  TARGET="${DATA_VERSION}"
  log "Pinned tizen-action version: ${TARGET} (${DATA_VERSION_SOURCE})"
fi
if [[ -z "${TARGET}" ]]; then
  command -v sdb >/dev/null 2>&1 || die "sdb not found; pass --target VERSION to choose the tizen-action version"
  SDB_CMD=(sdb)
  if [[ -n "${SDB_SERIAL:-}" ]]; then
    SDB_CMD=(sdb -s "${SDB_SERIAL}")
  else
    DEVICE_COUNT=$(sdb devices 2>/dev/null | tail -n +2 | grep -cw "device" || true)
    if [[ "${DEVICE_COUNT}" -eq 0 ]]; then
      die "no device connected; pass --target VERSION to choose the tizen-action version"
    elif [[ "${DEVICE_COUNT}" -gt 1 ]]; then
      die "${DEVICE_COUNT} devices connected; set SDB_SERIAL or pass --target VERSION"
    fi
  fi
  # rpm reports a missing package as prose on stdout, so require a leading digit.
  TARGET=$("${SDB_CMD[@]}" shell "rpm -q --qf '%{VERSION}' tizen-action" </dev/null 2>/dev/null |
           tr -d '\r' | head -1) || true
  [[ "${TARGET}" =~ ^[0-9] ]] || die "could not read the tizen-action version from the device (is it reachable and is tizen-action installed?)"
  log "Device tizen-action version: ${TARGET}"
fi
[[ "${TARGET}" =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "invalid version '${TARGET}'"

# --- Pick the matching data version --------------------------------------
# Exact match first; otherwise the highest same-<major>.<minor> version that
# is not newer than the target (REQUIREMENTS pins compatibility to a minor).
CHOSEN=""
TARGET_MM="${TARGET%.*}"
while read -r v; do
  [[ -z "${v}" ]] && continue
  if [[ "${v}" == "${TARGET}" ]]; then CHOSEN="${v}"; break; fi
  if [[ "${v%.*}" == "${TARGET_MM}" ]] &&
     [[ "$(printf '%s\n%s\n' "${v}" "${TARGET}" | sort -V | head -1)" == "${v}" ]]; then
    CHOSEN="${v}"   # ascending order, so the last hit is the highest
  fi
done < <(available_versions)

if [[ -z "${CHOSEN}" ]]; then
  echo "error: no schema data for tizen-action ${TARGET} in ${DATA_REPO}." >&2
  echo "       available versions:" >&2
  available_versions | sed 's/^/         /' >&2
  exit 1
fi
if [[ "${CHOSEN}" != "${TARGET}" ]]; then
  log "No exact match for ${TARGET}; using ${CHOSEN} (same ${TARGET_MM}.x line)."
fi

# --- Install into the data directory --------------------------------------
if [[ -f "${DATA_DIR}/DATA_VERSION" ]] &&
   [[ "$(cat "${DATA_DIR}/DATA_VERSION")" == "${CHOSEN}" ]] &&
   diff -rq -x DATA_VERSION -x DATA_SOURCE "${CACHE_DIR}/${CHOSEN}" "${DATA_DIR}" >/dev/null 2>&1; then
  log "Schema data ${CHOSEN} already installed in ${DATA_DIR}."
else
  # Refusing to wipe an arbitrary directory: only the compiler's own data dir,
  # an explicitly requested one, or a previous sync target is replaced.
  if [[ -e "${DATA_DIR}" && "${DATA_DIR_SET}" -eq 0 && "${DATA_DIR}" != "${INSTALL_DIR}/data" ]]; then
    die "refusing to replace ${DATA_DIR}; pass --data-dir to confirm"
  fi
  TMP_DIR="${DATA_DIR}.sync.$$"
  rm -rf "${TMP_DIR}"
  mkdir -p "$(dirname "${DATA_DIR}")"
  cp -R "${CACHE_DIR}/${CHOSEN}" "${TMP_DIR}"
  echo "${CHOSEN}" > "${TMP_DIR}/DATA_VERSION"
  echo "${DATA_REPO} ${DATA_REPO_BRANCH} $(git -C "${CACHE_DIR}" rev-parse --short HEAD 2>/dev/null || echo '?')" > "${TMP_DIR}/DATA_SOURCE"
  rm -rf "${DATA_DIR}"
  mv "${TMP_DIR}" "${DATA_DIR}"
  log "Installed schema data ${CHOSEN} into ${DATA_DIR}" \
      "($(ls "${DATA_DIR}/actions" | wc -l | tr -d ' ') actions," \
      "$(ls "${DATA_DIR}/entities" | wc -l | tr -d ' ') entities)."
fi

if [[ -n "${ACTIONC_DATA_DIR:-}" && "${ACTIONC_DATA_DIR}" != "${DATA_DIR}" ]]; then
  warn "ACTIONC_DATA_DIR=${ACTIONC_DATA_DIR} points elsewhere; actionc will not read ${DATA_DIR}."
fi
