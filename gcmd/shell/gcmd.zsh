# gcmd shell integration for zsh.
#
# Add gcmd/bin to PATH, then source this file from ~/.zshrc:
#   source "/path/to/gcmd-command-library/gcmd/shell/gcmd.zsh"
#
# The app is launched only when a shortcut is pressed:
#   Ctrl-G  Open command search
#   Ctrl-X  Open the save editor with the current input

if (( $+commands[gcmd] )); then
  function _gcmd_search_widget() {
    zle -I
    gcmd launch search
    zle reset-prompt
  }

  function _gcmd_save_widget() {
    if [[ -z "$BUFFER" ]]; then
      zle -M "gcmd: current input is empty"
      return
    fi
    zle -I
    gcmd launch save \
      --command "$BUFFER" \
      --cwd "$PWD" \
      --shell "${SHELL:t}"
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
