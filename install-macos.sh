#!/usr/bin/env bash
#
# macOS installation script for the Tizen Action Compiler.
# Copies actionc, action2tidl, and tidlc (Mach-O x86_64) plus actionc-sync to
# ~/.action-tools and updates the login-shell profiles.
#
# Differences from install.sh (Linux):
#   - binaries come from bin/macos/
#   - macOS terminals open login shells: zsh (the default shell) reads
#     ~/.zprofile and login bash reads ~/.bash_profile, neither reads ~/.bashrc,
#     so the environment goes into those two files (as the Tizen SDK tidlc
#     package for macOS does)
#   - BSD sed has no GNU-style `sed -i`, so profile blocks are rewritten through
#     a temporary file
#   - the binaries are x86_64 only: Apple silicon needs Rosetta 2
#   - the Gatekeeper quarantine flag is cleared from the copied binaries so a
#     repository downloaded as a zip does not get "cannot be opened" dialogs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.action-tools"
BIN_DIR="${SCRIPT_DIR}/bin/macos"
COMPILER_VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")
# The bundled binaries are linked with LC_BUILD_VERSION minos 26.0.
MIN_MACOS_MAJOR=26

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this script is for macOS. Use ./install.sh on Linux or install.bat on Windows." >&2
  exit 1
fi

echo "=== Installing Tizen Action Compiler v${COMPILER_VERSION} (macOS) ==="
echo "Target directory: ${INSTALL_DIR}"

# --- Host checks ---------------------------------------------------------
MACOS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "0")
if [[ "${MACOS_VERSION%%.*}" -lt "${MIN_MACOS_MAJOR}" ]]; then
  echo "warning: macOS ${MACOS_VERSION} detected; the bundled binaries are built for macOS ${MIN_MACOS_MAJOR} or later" \
       "and may fail to start." >&2
fi

if [[ "$(uname -m)" == "arm64" ]] && ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  echo "warning: Apple silicon without Rosetta 2 detected. The bundled binaries are x86_64 and need Rosetta 2:" >&2
  echo "           softwareupdate --install-rosetta --agree-to-license" >&2
fi

mkdir -p "${INSTALL_DIR}"

# --- Copy binaries ------------------------------------------------------
echo "[1/4] Copying binaries and version info..."
cp "${BIN_DIR}/actionc" "${INSTALL_DIR}/"
cp "${BIN_DIR}/action2tidl" "${INSTALL_DIR}/"
cp "${BIN_DIR}/tidlc" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/actionc-sync.sh" "${INSTALL_DIR}/actionc-sync"
cp "${SCRIPT_DIR}/data-repo.conf" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/VERSION" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/REQUIREMENTS" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/LICENSE" "${INSTALL_DIR}/"

chmod +x "${INSTALL_DIR}/actionc" "${INSTALL_DIR}/action2tidl" "${INSTALL_DIR}/tidlc" "${INSTALL_DIR}/actionc-sync"
xattr -d com.apple.quarantine "${INSTALL_DIR}/actionc" "${INSTALL_DIR}/action2tidl" "${INSTALL_DIR}/tidlc" 2>/dev/null || true
echo "Binaries and version info copied."

# --- Setup Environment Variables in shell configurations -----------------
echo "[2/4] Setting up environment variables..."

# Same profiles the Tizen SDK tidlc package for macOS writes to: zsh (the
# default shell since Catalina) reads ~/.zprofile and login bash reads
# ~/.bash_profile. Both are created when missing.
PROFILES=("${HOME}/.zprofile" "${HOME}/.bash_profile")

setup_config_file() {
  local conf_file="$1"
  local tmp_file
  echo "Updating ${conf_file}..."
  touch "${conf_file}"

  # Remove any existing Tizen Action Compiler block (same markers as install.sh)
  # to keep the profile duplicate-free. BSD sed cannot edit in place portably.
  tmp_file=$(mktemp "${conf_file}.XXXXXX")
  sed '/# Tizen Action Compiler/,/export ACTIONC_TIDLC/d' "${conf_file}" > "${tmp_file}"
  mv "${tmp_file}" "${conf_file}"

  {
    echo ""
    echo "# Tizen Action Compiler"
    echo "export PATH=\"\${HOME}/.action-tools:\${PATH}\""
    echo "export ACTIONC_DATA_DIR=\"\${HOME}/.action-tools/data\""
    echo "export ACTIONC_ACTION2TIDL=\"\${HOME}/.action-tools/action2tidl\""
    echo "export ACTIONC_TIDLC=\"\${HOME}/.action-tools/tidlc\""
  } >> "${conf_file}"
}

for profile in "${PROFILES[@]}"; do
  setup_config_file "${profile}"
done

# --- Verify -------------------------------------------------------------
echo "[3/4] Verifying installation..."
export PATH="${INSTALL_DIR}:${PATH}"
export ACTIONC_DATA_DIR="${INSTALL_DIR}/data"
export ACTIONC_ACTION2TIDL="${INSTALL_DIR}/action2tidl"
export ACTIONC_TIDLC="${INSTALL_DIR}/tidlc"

if command -v actionc >/dev/null && command -v action2tidl >/dev/null && command -v tidlc >/dev/null &&
   actionc -v >/dev/null 2>&1; then
  echo "Verification successful! All binaries are responsive."
  echo "  Compiler version: ${COMPILER_VERSION}"
  echo "  actionc:           $(actionc -v 2>/dev/null || echo 'installed')"
  echo "  action2tidl:       $(action2tidl --version 2>/dev/null || echo 'installed')"
  echo "  tidlc:             $(tidlc -v 2>&1 | grep '^tidlc' | head -1 || echo 'installed')"
  echo ""
  echo "  Target requirements for this compiler release:"
  grep -v '^[[:space:]]*#' "${SCRIPT_DIR}/REQUIREMENTS" | grep -v '^[[:space:]]*$' | sed 's/^/    /'
else
  echo "warning: Verification failed. The binaries could not be run from ${INSTALL_DIR}." >&2
  echo "         On Apple silicon make sure Rosetta 2 is installed; on macOS older than" >&2
  echo "         ${MIN_MACOS_MAJOR} the bundled binaries are not supported." >&2
fi

# --- Fetch the schema data ------------------------------------------------
# The schemas are not part of the compiler; actionc-sync fetches the set
# matching the attached device's tizen-action from the data repository. Best
# effort: without a device, network, or matching version the install still
# succeeds, but actionc has nothing to compile until actionc-sync has run
# (data from an earlier install, if any, is left in place).
echo "[4/4] Fetching schema data for the attached device's tizen-action..."
if "${INSTALL_DIR}/actionc-sync"; then
  :
else
  echo "warning: schema data not fetched; actionc needs it. Run 'actionc-sync' once a device is attached" >&2
  echo "         (or set DATA_VERSION in ${INSTALL_DIR}/data-repo.conf to build without a device)." >&2
fi

echo ""
echo "================================================================="
echo " Installation complete!"
echo " Please run the following command to apply PATH changes immediately:"
echo "   source ~/.zprofile"
echo " (bash users: source ~/.bash_profile)"
echo ""
echo " To check the installed compiler version later:"
echo "   cat ~/.action-tools/VERSION"
echo ""
echo " Schema data follows the attached device's tizen-action; re-run"
echo " 'actionc-sync' after switching devices or after a device update."
echo "================================================================="
