#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
COMPLETION_DIR="$HOME/.zsh/completions"
ZSHRC="$HOME/.zshrc"

mkdir -p "$BIN_DIR" "$COMPLETION_DIR"
install -m 0755 "$ROOT/bin/ccs" "$BIN_DIR/ccs"
install -m 0644 "$ROOT/completions/_ccs" "$COMPLETION_DIR/_ccs"

if [[ ! -f "$ZSHRC" ]]; then
  touch "$ZSHRC"
fi

if ! grep -q 'ccswitch-cli-companion completion' "$ZSHRC"; then
  cat >> "$ZSHRC" <<'EOF'

# ccswitch-cli-companion completion
export PATH="$HOME/.local/bin:$PATH"
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
compinit -i
# end ccswitch-cli-companion completion
EOF
fi

cat <<EOF
Installed ccs to: $BIN_DIR/ccs
Installed zsh completion to: $COMPLETION_DIR/_ccs

Run this to use it now:
  source ~/.zshrc

Then try:
  ccs
  ccs <provider-name>
EOF
