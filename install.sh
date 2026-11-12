#!/usr/bin/env bash
#
# Installation script for the Tizen Action Compiler.
# Copies actionc, action2tidl, tidlc, and actionc-sync to ~/.action-tools and updates shell startup files.
# The schema data is not shipped with the compiler: actionc-sync fetches it at the end.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.action-tools"
COMPILER_VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "unknown")

echo "=== Installing Tizen Action Compiler v${COMPILER_VERSION} ==="
echo "Target directory: ${INSTALL_DIR}"

mkdir -p "${INSTALL_DIR}"

# --- Copy binaries ------------------------------------------------------
echo "[1/4] Copying binaries and version info..."
cp "${SCRIPT_DIR}/bin/linux/actionc" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/bin/linux/action2tidl" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/bin/linux/tidlc" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/actionc-sync.sh" "${INSTALL_DIR}/actionc-sync"
cp "${SCRIPT_DIR}/data-repo.conf" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/VERSION" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/REQUIREMENTS" "${INSTALL_DIR}/"
cp "${SCRIPT_DIR}/LICENSE" "${INSTALL_DIR}/"

chmod +x "${INSTALL_DIR}/actionc" "${INSTALL_DIR}/action2tidl" "${INSTALL_DIR}/tidlc" "${INSTALL_DIR}/actionc-sync"
echo "Binaries and version info copied."

# --- Setup Environment Variables in shell configurations -----------------
echo "[2/4] Setting up environment variables..."

BASHRC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"

setup_config_file() {
  local conf_file="$1"
  if [[ -f "${conf_file}" ]]; then
    echo "Updating ${conf_file}..."
    # Remove any existing Tizen Action Compiler block to maintain clean, duplicate-free profiles
    sed -i '/# Tizen Action Compiler/,/export ACTIONC_TIDLC/d' "${conf_file}"
    
    echo "" >> "${conf_file}"
    echo "# Tizen Action Compiler" >> "${conf_file}"
    echo "export PATH=\"\${HOME}/.action-tools:\${PATH}\"" >> "${conf_file}"
    echo "export ACTIONC_DATA_DIR=\"\${HOME}/.action-tools/data\"" >> "${conf_file}"
    echo "export ACTIONC_ACTION2TIDL=\"\${HOME}/.action-tools/action2tidl\"" >> "${conf_file}"
    echo "export ACTIONC_TIDLC=\"\${HOME}/.action-tools/tidlc\"" >> "${conf_file}"
  fi
}

setup_config_file "${BASHRC}"
setup_config_file "${PROFILE}"

# --- Verify -------------------------------------------------------------
echo "[3/4] Verifying installation..."
export PATH="${INSTALL_DIR}:${PATH}"
export ACTIONC_DATA_DIR="${INSTALL_DIR}/data"
export ACTIONC_ACTION2TIDL="${INSTALL_DIR}/action2tidl"
export ACTIONC_TIDLC="${INSTALL_DIR}/tidlc"

if command -v actionc >/dev/null && command -v action2tidl >/dev/null && command -v tidlc >/dev/null; then
  echo "Verification successful! All binaries are responsive."
  echo "  Compiler version: ${COMPILER_VERSION}"
  echo "  actionc:           $(actionc -v 2>/dev/null || echo 'installed')"
  echo "  action2tidl:       $(action2tidl --version 2>/dev/null || echo 'installed')"
  echo "  tidlc:             $(tidlc -v 2>&1 | grep '^tidlc' | head -1 || echo 'installed')"
  echo ""
  echo "  Target requirements for this compiler release:"
  grep -v '^\s*#' "${SCRIPT_DIR}/REQUIREMENTS" | grep -v '^\s*$' | sed 's/^/    /'
else
  echo "warning: Verification failed. Please make sure ~/.action-tools is added to your PATH manually."
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
echo "   source ~/.bashrc"
echo ""
echo " To check the installed compiler version later:"
echo "   cat ~/.action-tools/VERSION"
echo ""
echo " Schema data follows the attached device's tizen-action; re-run"
echo " 'actionc-sync' after switching devices or after a device update."
echo "================================================================="
