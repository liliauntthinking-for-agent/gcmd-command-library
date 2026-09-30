#!/bin/zsh

# Transparent gcmd SSH bridge.
#
# Wraps interactive `ssh` calls so that Ctrl-G / Ctrl-X work on the remote
# host without requiring `gcmd ssh` explicitly.
#
# Set GCMD_NO_BRIDGE=1 to bypass (e.g. GCMD_NO_BRIDGE=1 ssh host).

function ssh() {
  if [[ "${GCMD_NO_BRIDGE:-0}" == "1" ]]; then
    command ssh "$@"
    return
  fi

  # Detect whether a remote command is being executed.
  # If yes, this is non-interactive; run plain ssh.
  local -a args=("$@")
  local arg
  local seen_host=0
  local has_remote_command=0
  local no_more_options=0

  for arg in "${args[@]}"; do
    if [[ "$no_more_options" -eq 1 ]]; then
      # After --, everything is the remote command.
      has_remote_command=1
      break
    fi
    case "$arg" in
      --)
        no_more_options=1
        ;;
      -*)
        # Option or option with inline value; skip.
        ;;
      *)
        if [[ "$seen_host" -eq 0 ]]; then
          seen_host=1
        else
          # Argument after host = remote command.
          has_remote_command=1
          break
        fi
        ;;
    esac
  done

  if [[ "$has_remote_command" -eq 1 ]]; then
    command ssh "$@"
  else
    gcmd ssh "$@"
  fi
}
