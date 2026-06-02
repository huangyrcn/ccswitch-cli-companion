#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${CCS_INSTALL_BIN_DIR:-$HOME/.local/bin}"
ZSH_COMPLETION_DIR="${CCS_ZSH_COMPLETION_DIR:-$HOME/.zsh/completions}"
BASH_COMPLETION_DIR="${CCS_BASH_COMPLETION_DIR:-$HOME/.local/share/bash-completion/completions}"
ZSHRC="$HOME/.zshrc"
BASHRC="$HOME/.bashrc"
SHELL_TARGET="auto"
INSTALL_COMPLETION=1

usage() {
  cat <<'EOF'
Usage: ./install.sh [--shell auto|zsh|bash|both] [--no-completion]

Options:
  --shell auto       Install completion for the current shell (default)
  --shell zsh        Install zsh completion and update ~/.zshrc
  --shell bash       Install bash completion and update ~/.bashrc
  --shell both       Install both zsh and bash completions
  --no-completion    Install only the ccs executable
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)
      if [[ $# -lt 2 ]]; then
        echo "--shell requires one of: auto, zsh, bash, both" >&2
        exit 1
      fi
      SHELL_TARGET="$2"
      shift 2
      ;;
    --no-completion)
      INSTALL_COMPLETION=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$SHELL_TARGET" in
  auto|zsh|bash|both) ;;
  *)
    echo "Unsupported shell target: $SHELL_TARGET" >&2
    usage >&2
    exit 1
    ;;
esac

mkdir -p "$BIN_DIR"
install -m 0755 "$ROOT/bin/ccs" "$BIN_DIR/ccs"

ensure_path_block() {
  local rc_file="$1"
  local label="$2"
  if [[ ! -f "$rc_file" ]]; then
    touch "$rc_file"
  fi
  if ! grep -q "$label path" "$rc_file"; then
    cat >> "$rc_file" <<'EOF'

# ccswitch-cli-companion path
export PATH="$HOME/.local/bin:$PATH"
# end ccswitch-cli-companion path
EOF
  fi
}

remove_block() {
  local rc_file="$1"
  local start_marker="$2"
  local end_marker="$3"
  [[ -f "$rc_file" ]] || return 0
  python3 - "$rc_file" "$start_marker" "$end_marker" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
start = sys.argv[2]
end = sys.argv[3]
lines = path.read_text().splitlines()
out = []
skip = False
changed = False
for line in lines:
    if line == start:
        skip = True
        changed = True
        continue
    if skip:
        if line == end:
            skip = False
        continue
    out.append(line)
if changed:
    path.write_text("\n".join(out).rstrip() + "\n")
PY
}

remove_legacy_blocks() {
  remove_block "$ZSHRC" "# ccswitch-cli-companion completion" "# end ccswitch-cli-companion completion"
  remove_block "$ZSHRC" "# ccs-cli completion" "# end ccs-cli completion"
}

install_zsh_completion() {
  mkdir -p "$ZSH_COMPLETION_DIR"
  install -m 0644 "$ROOT/completions/_ccs" "$ZSH_COMPLETION_DIR/_ccs"
  ensure_path_block "$ZSHRC" "ccswitch-cli-companion"
  if ! grep -q 'ccswitch-cli-companion zsh completion' "$ZSHRC"; then
    cat >> "$ZSHRC" <<'EOF'

# ccswitch-cli-companion zsh completion
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
compinit -i
# end ccswitch-cli-companion zsh completion
EOF
  fi
}

install_bash_completion() {
  mkdir -p "$BASH_COMPLETION_DIR"
  install -m 0644 "$ROOT/completions/ccs.bash" "$BASH_COMPLETION_DIR/ccs"
  ensure_path_block "$BASHRC" "ccswitch-cli-companion"
  if ! grep -q 'ccswitch-cli-companion bash completion' "$BASHRC"; then
    cat >> "$BASHRC" <<'EOF'

# ccswitch-cli-companion bash completion
if [ -f "$HOME/.local/share/bash-completion/completions/ccs" ]; then
  source "$HOME/.local/share/bash-completion/completions/ccs"
fi
# end ccswitch-cli-companion bash completion
EOF
  fi
}

resolved_shell_target() {
  if [[ "$SHELL_TARGET" != "auto" ]]; then
    printf '%s\n' "$SHELL_TARGET"
    return
  fi

  case "${SHELL##*/}" in
    zsh) printf 'zsh\n' ;;
    bash) printf 'bash\n' ;;
    *) printf 'zsh\n' ;;
  esac
}

installed_completion="none"
if [[ "$INSTALL_COMPLETION" -eq 1 ]]; then
  remove_legacy_blocks
  case "$(resolved_shell_target)" in
    zsh)
      install_zsh_completion
      installed_completion="zsh"
      ;;
    bash)
      install_bash_completion
      installed_completion="bash"
      ;;
    both)
      install_zsh_completion
      install_bash_completion
      installed_completion="zsh,bash"
      ;;
  esac
fi

cat <<EOF
Installed ccs to: $BIN_DIR/ccs
Installed completion: $installed_completion

Run one of these to use it now:
  source ~/.zshrc
  source ~/.bashrc

Then try:
  ccs
  ccs <provider-name>
EOF
