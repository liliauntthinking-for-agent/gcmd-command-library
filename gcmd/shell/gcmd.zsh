# gcmd shell integration for zsh.
#
# Source this file from ~/.zshrc:
#   source "/path/to/gcmd-command-library/gcmd/shell/gcmd.zsh"
#
# The app is launched only when a shortcut is pressed:
#   Ctrl-G  Open command search
#   Ctrl-X  Open the save editor with the current input

typeset -g _GCMD_INTEGRATION_DIR="${${(%):-%x}:A:h}"
typeset -g _GCMD_PACKAGE_DIR="$_GCMD_INTEGRATION_DIR"

# Repository checkouts keep the shell file at gcmd/shell/gcmd.zsh.
if [[ ! -f "$_GCMD_PACKAGE_DIR/gcmd" && -f "$_GCMD_INTEGRATION_DIR/../gcmd" ]]; then
  _GCMD_PACKAGE_DIR="$_GCMD_INTEGRATION_DIR/.."
fi
if [[ ! -f "$_GCMD_PACKAGE_DIR/gcmd" && -f "$_GCMD_INTEGRATION_DIR/../../build/gcmd" ]]; then
  _GCMD_PACKAGE_DIR="$_GCMD_INTEGRATION_DIR/../../build"
fi

_GCMD_PACKAGE_DIR="${_GCMD_PACKAGE_DIR:A}"
if [[ -d "$_GCMD_PACKAGE_DIR/gcmd.app" ]]; then
  export GCMD_APP="$_GCMD_PACKAGE_DIR/gcmd.app"
fi

if [[ -x "$_GCMD_PACKAGE_DIR/gcmd" ]]; then
  typeset -g _GCMD_CLI="$_GCMD_PACKAGE_DIR/gcmd"
  path=("$_GCMD_PACKAGE_DIR" $path)
  export PATH
else
  _GCMD_CLI="$(command -v gcmd)"
fi

if [[ -n "$_GCMD_CLI" ]]; then
  function _gcmd_launch() {
    local output
    if ! output="$("$_GCMD_CLI" launch "$@" 2>&1)"; then
      zle -M "gcmd: $output"
    fi
  }

  function _gcmd_search_widget() {
    zle -I
    _gcmd_launch search
    zle reset-prompt
  }

  function _gcmd_save_widget() {
    if [[ -z "$BUFFER" ]]; then
      zle -M "gcmd: current input is empty"
      return
    fi
    zle -I
    _gcmd_launch save \
      --command "$BUFFER" \
      --cwd "$PWD"
    zle reset-prompt
  }

  zle -N gcmd-search _gcmd_search_widget
  zle -N gcmd-save _gcmd_save_widget

  # Use single control bytes instead of ESC-prefixed sequences. In vi mode,
  # ESC switches keymaps before a longer CSI sequence can be completed.
  for keymap in emacs viins vicmd; do
    bindkey -M "$keymap" $'\x1f' gcmd-search
    bindkey -M "$keymap" $'\x1e' gcmd-save
    bindkey -M "$keymap" $'\x07' gcmd-search
    bindkey -M "$keymap" $'\x18' gcmd-save
  done
fi

# Transparent SSH bridge: wraps interactive `ssh` so Ctrl-G / Ctrl-X work remotely.
# Set GCMD_NO_BRIDGE=1 to bypass for a single call.
if [[ "${GCMD_NO_BRIDGE:-0}" != "1" && -x "${_GCMD_CLI}" ]]; then
  source "$(dirname "${(%):-%x}")/gcmd-ssh.zsh"
fi
