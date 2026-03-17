#!/bin/bash

SUDOERS_FILE="/etc/sudoers.d/nopasswd_$(whoami)"
CURRENT_USER=$(whoami)
CONFIG_DIR="$HOME/.config/sudotoggle"
CONFIG_FILE="$CONFIG_DIR/config"
HOOK_FILE="$CONFIG_DIR/hook.sh"

# ─── Config ────────────────────────────────────────────────────────────────────

init_config() {
  mkdir -p "$CONFIG_DIR"
  [ -f "$CONFIG_FILE" ] || touch "$CONFIG_FILE"
}

get_config() {
  grep "^$1=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2
}

set_config() {
  init_config
  if grep -q "^$1=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^$1=.*|$1=$2|" "$CONFIG_FILE"
  else
    echo "$1=$2" >>"$CONFIG_FILE"
  fi
}

# ─── Helpers ───────────────────────────────────────────────────────────────────

file_exists() {
  sudo test -f "$SUDOERS_FILE"
}

detect_rc() {
  case "$(basename "$SHELL")" in
  zsh) echo "$HOME/.zshrc" ;;
  bash) echo "$HOME/.bashrc" ;;
  *) echo "" ;;
  esac
}

format_timestamp() {
  date -d "@$1" "+%Y-%m-%d %H:%M:%S" 2>/dev/null ||
    date -r "$1" "+%Y-%m-%d %H:%M:%S" 2>/dev/null
}

# ─── Hook ──────────────────────────────────────────────────────────────────────

write_hook_file() {
  cat >"$HOOK_FILE" <<'HOOK'
# sudotoggle shell hook — do not edit manually
_sudotoggle_preexec() {
    local cmd="$1"
    local CONFIG_FILE="$HOME/.config/sudotoggle/config"
    local SUDOERS_FILE="/etc/sudoers.d/nopasswd_$(whoami)"

    # Only react to commands containing sudo
    echo "$cmd" | grep -qw "sudo" || return 0

    # If the sudoers file does not exist — do nothing
    sudo test -f "$SUDOERS_FILE" 2>/dev/null || return 0

    local debug expiry now
    debug=$(grep "^DEBUG=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
    expiry=$(grep "^EXPIRY=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2)
    now=$(date +%s)

    # Check timer expiry (regardless of debug mode)
    if [ -n "$expiry" ] && [ "$expiry" != "unlimited" ]; then
        if [ "$now" -ge "$expiry" ]; then
            sudo rm -f "$SUDOERS_FILE" 2>/dev/null
            sudo -k 2>/dev/null
            sed -i "s|^EXPIRY=.*|EXPIRY=unlimited|" "$CONFIG_FILE" 2>/dev/null
            printf '\033[33m[sudotoggle] ⏰ NOPASSWD expired — disabled automatically.\033[0m\n'
            return 0
        fi
    fi

    # Print debug line if enabled
    [ "$debug" = "on" ] || return 0

    if [ -n "$expiry" ] && [ "$expiry" != "unlimited" ]; then
        local until_str remaining
        until_str=$(date -d "@$expiry" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
                 || date -r "$expiry"  "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
        remaining=$(( expiry - now ))
        printf '\033[36m[sudotoggle] 🔓 NOPASSWD ACTIVE — until %s (%ds remaining)\033[0m\n' \
            "$until_str" "$remaining"
    else
        printf '\033[36m[sudotoggle] 🔓 NOPASSWD ACTIVE — unlimited\033[0m\n'
    fi
}

if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null
    add-zsh-hook preexec _sudotoggle_preexec 2>/dev/null
elif [ -n "$BASH_VERSION" ]; then
    trap '_sudotoggle_preexec "$BASH_COMMAND"' DEBUG
fi
HOOK
}

install_hook() {
  local rc
  rc=$(detect_rc)
  if [ -z "$rc" ]; then
    echo "[-] Automatic hook installation is only supported for zsh/bash."
    return 1
  fi

  if grep -q "sudotoggle" "$rc" 2>/dev/null; then
    write_hook_file # update hook contents
    return 0
  fi

  write_hook_file
  printf '\n# sudotoggle hook\n[ -f "%s" ] && source "%s"\n' \
    "$HOOK_FILE" "$HOOK_FILE" >>"$rc"

  echo "[+] Hook installed into $rc"
  echo "[*] Run 'source $rc' or open a new terminal to activate."
}

uninstall_hook() {
  local rc
  rc=$(detect_rc)

  # only remove if both debug=off and no active timer
  local debug expiry
  debug=$(get_config "DEBUG")
  expiry=$(get_config "EXPIRY")

  if [ "$debug" = "on" ] || ([ -n "$expiry" ] && [ "$expiry" != "unlimited" ]); then
    return 0 # hook is still needed
  fi

  if [ -n "$rc" ] && grep -q "sudotoggle" "$rc" 2>/dev/null; then
    sed -i '/# sudotoggle hook/d;/sudotoggle.*hook/d' "$rc"
    echo "[+] Hook removed from $rc"
    echo "[*] Run 'source $rc' or open a new terminal to deactivate."
  fi
}

# ─── Commands ──────────────────────────────────────────────────────────────────

cmd_on() {
  local expiry="${1:-unlimited}"

  if file_exists; then
    echo "[*] Passwordless sudo is already enabled for '$CURRENT_USER'."
    if [ "$expiry" != "unlimited" ]; then
      set_config "EXPIRY" "$expiry"
      install_hook
      local until_str
      until_str=$(format_timestamp "$expiry")
      echo "[*] Expiry time updated: $until_str"
    fi
    exit 0
  fi

  echo "[*] Enter your password to enable passwordless sudo:"
  sudo -v || {
    echo "[-] Authentication failed."
    exit 1
  }

  echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "$SUDOERS_FILE" >/dev/null
  sudo chmod 440 "$SUDOERS_FILE"

  if ! sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    echo "[-] Sudoers file syntax error, rolling back."
    sudo rm -f "$SUDOERS_FILE"
    exit 1
  fi

  set_config "EXPIRY" "$expiry"

  if [ "$expiry" != "unlimited" ]; then
    install_hook
    local until_str remaining
    until_str=$(format_timestamp "$expiry")
    remaining=$((expiry - $(date +%s)))
    echo "[+] Passwordless sudo enabled for '$CURRENT_USER'."
    echo "[*] Active until: $until_str (${remaining}s remaining)"
  else
    echo "[+] Passwordless sudo enabled for '$CURRENT_USER' (unlimited)."
  fi
}

cmd_off() {
  if ! file_exists; then
    echo "[*] Passwordless sudo is already disabled for '$CURRENT_USER'."
    sudo -k 2>/dev/null
    exit 0
  fi

  sudo rm -f "$SUDOERS_FILE"

  if file_exists; then
    echo "[-] Failed to remove sudoers file: $SUDOERS_FILE"
    exit 1
  fi

  set_config "EXPIRY" "unlimited"
  sudo -k
  uninstall_hook

  echo "[+] Passwordless sudo disabled for '$CURRENT_USER'."
  echo "[*] Other open terminals may require 'sudo -k' to reset their cache."
}

cmd_debug() {
  case "$1" in
  on)
    set_config "DEBUG" "on"
    install_hook
    echo "[+] Debug mode enabled."
    ;;
  off)
    set_config "DEBUG" "off"
    uninstall_hook
    echo "[+] Debug mode disabled."
    ;;
  *)
    echo "Usage: $(basename "$0") -debug [on|off]"
    exit 1
    ;;
  esac
}

cmd_status() {
  local expiry debug now
  expiry=$(get_config "EXPIRY")
  debug=$(get_config "DEBUG")
  now=$(date +%s)

  echo "─────────────────────────────────────"
  if file_exists; then
    echo "  NOPASSWD:  ✅ ENABLED"
    if [ -n "$expiry" ] && [ "$expiry" != "unlimited" ]; then
      local until_str remaining
      until_str=$(format_timestamp "$expiry")
      if [ "$now" -ge "$expiry" ]; then
        echo "  Expiry:    $until_str  ⚠ EXPIRED (will disable on next sudo)"
      else
        remaining=$((expiry - now))
        echo "  Expiry:    $until_str  (${remaining}s remaining)"
      fi
    else
      echo "  Expiry:    unlimited"
    fi
  else
    echo "  NOPASSWD:  ❌ DISABLED"
  fi

  echo "  Debug:     ${debug:-off}"
  echo "  User:      $CURRENT_USER"
  echo "  File:      $SUDOERS_FILE"
  echo "─────────────────────────────────────"
}

cmd_help() {
  cat <<EOF
sudotoggle — manage sudo NOPASSWD mode

USAGE:
    sudotoggle <command> [options]

COMMANDS:

  -on
        Enable NOPASSWD with no time limit.
        Will prompt for password once on first use.
        Example:
            sudotoggle -on

  -on -time <seconds>
        Enable NOPASSWD for the given number of seconds.
        After expiry, NOPASSWD will be disabled automatically
        on the next sudo command (requires hook to be installed).
        Examples:
            sudotoggle -on -time 3600      # for 1 hour
            sudotoggle -on -time 300       # for 5 minutes

  -on -timef <HH:MM>
        Enable NOPASSWD until the specified local time.
        If the time has already passed today, it will be set for tomorrow.
        Examples:
            sudotoggle -on -timef 18:30    # until 18:30
            sudotoggle -on -timef 23:00    # until 23:00

  -off
        Disable NOPASSWD and immediately reset the sudo cache.
        Example:
            sudotoggle -off

  -debug on
        Enable debug mode. Before every command containing sudo,
        a colored status line will be printed to the terminal:
            [sudotoggle] 🔓 NOPASSWD ACTIVE — until 2025-03-17 18:30:00 (1234s remaining)
            [sudotoggle] 🔓 NOPASSWD ACTIVE — unlimited
        Also handles automatic disabling when the timer expires.
        Example:
            sudotoggle -debug on

  -debug off
        Disable debug mode and remove the hook from the shell rc file.
        Example:
            sudotoggle -debug off

  -status
        Show current state: whether NOPASSWD is enabled, expiry time,
        remaining time, and debug mode status.
        Example:
            sudotoggle -status

  -help
        Show this help message.

FILES:
    /etc/sudoers.d/nopasswd_$CURRENT_USER   — sudoers rule
    ~/.config/sudotoggle/config              — configuration (debug, expiry)
    ~/.config/sudotoggle/hook.sh             — shell hook (debug/timer)

NOTES:
    - Auto-disable on timer expiry triggers on the next sudo command
      if the hook is installed (-debug on or -on -time/-timef).
    - After -off, other open terminals may require 'sudo -k'.
    - Supported shells for the hook: zsh, bash.
EOF
}

# ─── Entry point ───────────────────────────────────────────────────────────────

init_config

case "$1" in
-on)
  expiry="unlimited"
  case "$2" in
  -time)
    if [ -z "$3" ] || ! echo "$3" | grep -qE '^[0-9]+$'; then
      echo "[-] Please specify seconds. Example: -time 3600"
      exit 1
    fi
    expiry=$(($(date +%s) + $3))
    ;;
  -timef)
    if [ -z "$3" ] || ! echo "$3" | grep -qE '^[0-2][0-9]:[0-5][0-9]$'; then
      echo "[-] Please specify time in HH:MM format. Example: -timef 18:30"
      exit 1
    fi
    expiry=$(date -d "today $3" +%s 2>/dev/null)
    if [ -z "$expiry" ]; then
      echo "[-] Could not parse time '$3'."
      exit 1
    fi
    now=$(date +%s)
    [ "$expiry" -le "$now" ] && expiry=$(date -d "tomorrow $3" +%s 2>/dev/null)
    ;;
  esac
  cmd_on "$expiry"
  ;;
-off) cmd_off ;;
-debug) cmd_debug "$2" ;;
-status) cmd_status ;;
-help | --help | -h) cmd_help ;;
*)
  echo "Usage: $(basename "$0") [-on | -off | -debug on/off | -status | -help]"
  echo "Details: $(basename "$0") -help"
  exit 1
  ;;
esac
