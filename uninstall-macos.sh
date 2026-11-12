#!/usr/bin/env bash
#
# macOS uninstallation script for the Tizen Action Compiler.
# Removes ~/.action-tools and the environment setup added by install-macos.sh.

set -euo pipefail

INSTALL_DIR="${HOME}/.action-tools"
INSTALLED_VERSION=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")

echo "=== Uninstalling Tizen Action Compiler v${INSTALLED_VERSION} (macOS) ==="
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

# The profiles install-macos.sh writes to, plus ~/.bashrc and ~/.profile in
# case install.sh (Linux) was run on this machine earlier.
PROFILES=(
  "${HOME}/.zprofile"
  "${HOME}/.bash_profile"
  "${HOME}/.bashrc"
  "${HOME}/.profile"
)

cleanup_config_file() {
  local conf_file="$1"
  local tmp_file
  if [[ -f "${conf_file}" ]]; then
    if grep -q '# Tizen Action Compiler' "${conf_file}"; then
      echo "Updating ${conf_file}..."
      # Remove the block added by install-macos.sh. BSD sed cannot edit in place portably.
      tmp_file=$(mktemp "${conf_file}.XXXXXX")
      sed '/# Tizen Action Compiler/,/export ACTIONC_TIDLC/d' "${conf_file}" > "${tmp_file}"
      mv "${tmp_file}" "${conf_file}"
    else
      echo "No Tizen Action Compiler block in ${conf_file}; skipping."
    fi
  fi
}

for profile in "${PROFILES[@]}"; do
  cleanup_config_file "${profile}"
done

echo ""
echo "================================================================="
echo " Uninstallation complete!"
echo " Please open a new terminal (or run 'source ~/.zprofile') so the"
echo " PATH and ACTIONC_* variables are cleared from your session."
echo "================================================================="
