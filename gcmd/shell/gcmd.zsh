# gcmd shell integration for zsh.
#
# Add this directory's parent bin/ to PATH, then source this file from ~/.zshrc:
#   source "/path/to/gcmd/shell/gcmd.zsh"
#
# Default shortcuts:
#   Option-Space  Search and insert a command
#   Option-S      Save the current input line

if (( $+commands[gcmd] )); then
  function _gcmd_pick_widget() {
    local selected
    selected="$(gcmd pick --shell "${SHELL:t}" --cwd "$PWD")" || return
    if [[ -n "$selected" ]]; then
      BUFFER="$selected"
      CURSOR=${#BUFFER}
      zle redisplay
    fi
  }

  function _gcmd_save_widget() {
    if [[ -z "$BUFFER" ]]; then
      zle -M "gcmd: current input is empty"
      return
    fi
    local message
    message="$(gcmd save "$BUFFER" --shell "${SHELL:t}" --cwd "$PWD" 2>&1)" || {
      zle -M "$message"
      return
    }
    zle -M "$message"
    zle redisplay
  }

  zle -N gcmd-pick _gcmd_pick_widget
  zle -N gcmd-save _gcmd_save_widget

  # macOS Option+Space and Option+S commonly arrive as ESC-prefixed sequences.
  bindkey '^[ ' gcmd-pick
  bindkey '^[s' gcmd-save
fi
