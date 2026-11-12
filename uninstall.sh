#!/usr/bin/env bash
#
# Uninstallation script for the Tizen Action Compiler.
# Removes ~/.action-tools and the environment setup added by install.sh.

set -euo pipefail

INSTALL_DIR="${HOME}/.action-tools"
INSTALLED_VERSION=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")

echo "=== Uninstalling Tizen Action Compiler v${INSTALLED_VERSION} ==="
echo "Target directory: ${INSTALL_DIR}"

# --- Remove installed files ----------------------------------------------
echo "[1/2] Removing installed binaries and schema data..."
if [[ -d "${INSTALL_DIR}" ]]; then
  rm -rf "${INSTALL_DIR}"
  echo "Removed ${INSTALL_DIR}."
else
  echo "${INSTALL_DIR} not found; nothing to remove."
fi

# --- Remove Environment Variables from shell configurations --------------
echo "[2/2] Removing environment variables..."

BASHRC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"

cleanup_config_file() {
  local conf_file="$1"
  if [[ -f "${conf_file}" ]]; then
    if grep -q '# Tizen Action Compiler' "${conf_file}"; then
      echo "Updating ${conf_file}..."
      # Remove the block added by install.sh
      sed -i '/# Tizen Action Compiler/,/export ACTIONC_TIDLC/d' "${conf_file}"
    else
      echo "No Tizen Action Compiler block in ${conf_file}; skipping."
    fi
  fi
}

cleanup_config_file "${BASHRC}"
cleanup_config_file "${PROFILE}"

echo ""
echo "================================================================="
echo " Uninstallation complete!"
echo " Please restart your shell (or run 'source ~/.bashrc') so the"
echo " PATH and ACTIONC_* variables are cleared from your session."
echo "================================================================="
