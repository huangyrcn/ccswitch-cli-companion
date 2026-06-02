#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

DB="$TMPDIR_ROOT/cc-switch.db"
HOME_DIR="$TMPDIR_ROOT/home"
mkdir -p "$HOME_DIR/.cc-switch"
DB="$HOME_DIR/.cc-switch/cc-switch.db"

sqlite3 "$DB" <<'SQL'
CREATE TABLE providers (
  id TEXT NOT NULL,
  app_type TEXT NOT NULL,
  name TEXT NOT NULL,
  settings_config TEXT NOT NULL,
  sort_index INTEGER,
  is_current BOOLEAN NOT NULL DEFAULT 0,
  PRIMARY KEY (id, app_type)
);
INSERT INTO providers (id, app_type, name, settings_config, sort_index, is_current) VALUES
  ('buzz-id', 'claude', 'BUZZ', '{"env":{"ANTHROPIC_BASE_URL":"https://buzz.example/v1","ANTHROPIC_AUTH_TOKEN":"secret-buzz","ANTHROPIC_DEFAULT_SONNET_MODEL":"buzz-sonnet","ANTHROPIC_DEFAULT_OPUS_MODEL":"buzz-opus"}}', 1, 0),
  ('pixel-id', 'claude', 'ai-pixel', '{"env":{"ANTHROPIC_BASE_URL":"https://pixel.example/v1","ANTHROPIC_AUTH_TOKEN":"secret-pixel","ANTHROPIC_DEFAULT_SONNET_MODEL":"pixel-sonnet","ANTHROPIC_DEFAULT_OPUS_MODEL":"pixel-opus"}}', 2, 1),
  ('xiaomi-id', 'claude', 'Xiaomi MiMo Token Plan (China)', '{"env":{"ANTHROPIC_BASE_URL":"https://mimo.example/v1","ANTHROPIC_AUTH_TOKEN":"secret-mimo","ANTHROPIC_DEFAULT_SONNET_MODEL":"mimo-sonnet","ANTHROPIC_DEFAULT_OPUS_MODEL":"mimo-opus"}}', 3, 0),
  ('codex-id', 'codex', 'Not Claude', '{}', 4, 0);
SQL

run_with_home() {
  HOME="$HOME_DIR" "$@"
}

test_no_args_lists_providers() {
  local output
  output="$(run_with_home ccs)"
  [[ "$output" == *"BUZZ"* ]] || { echo "expected BUZZ in list" >&2; return 1; }
  [[ "$output" == *"ai-pixel"* ]] || { echo "expected ai-pixel in list" >&2; return 1; }
  [[ "$output" != *"Not Claude"* ]] || { echo "should not list non-Claude provider" >&2; return 1; }
}

test_provider_launch_writes_settings_and_calls_claude() {
  local stub_dir call_file settings_file
  stub_dir="$TMPDIR_ROOT/stub-bin"
  call_file="$TMPDIR_ROOT/claude-call.txt"
  settings_file="$TMPDIR_ROOT/settings-path.txt"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CCS_TEST_CALL_FILE"
if [[ "$1" != "--settings" || ! -s "$2" ]]; then
  echo "unexpected claude args: $*" >&2
  exit 2
fi
printf '%s\n' "$2" > "$CCS_TEST_SETTINGS_FILE"
python3 -m json.tool "$2" >/dev/null
SH
  chmod +x "$stub_dir/claude"

  PATH="$stub_dir:$PATH" \
  CCS_TEST_CALL_FILE="$call_file" \
  CCS_TEST_SETTINGS_FILE="$settings_file" \
  run_with_home ccs BUZZ >/tmp/ccs-test-launch.out

  grep -q -- '--settings' "$call_file" || { echo "claude was not called with --settings" >&2; return 1; }
  local tmp_settings
  tmp_settings="$(cat "$settings_file")"
  [[ ! -e "$tmp_settings" ]] || { echo "temporary settings file was not removed" >&2; return 1; }

  local output
  output="$(cat /tmp/ccs-test-launch.out)"
  [[ "$output" == *"Using provider: BUZZ (buzz-id)"* ]] || { echo "missing provider launch message" >&2; return 1; }
}

test_completion_rows_include_provider_metadata() {
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" zsh -fc 'source "$1" --rows' _ "$ROOT/completions/_ccs")"
  [[ "$output" == *$'BUZZ\t-'* ]] || { echo "completion rows missing BUZZ" >&2; return 1; }
  [[ "$output" == *"https://buzz.example/v1"* ]] || { echo "completion rows missing base url" >&2; return 1; }
}

test_bash_completion_completes_provider_names() {
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" bash -c '
    source "$1"
    COMP_WORDS=(ccs B)
    COMP_CWORD=1
    _ccs_bash_completion
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$ROOT/completions/ccs.bash")"
  [[ "$output" == *"BUZZ"* ]] || { echo "bash completion did not include BUZZ" >&2; return 1; }
}

test_bash_completion_escapes_provider_names_with_spaces() {
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" bash -c '
    source "$1"
    COMP_WORDS=(ccs Xi)
    COMP_CWORD=1
    _ccs_bash_completion
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$ROOT/completions/ccs.bash")"
  [[ "$output" == *"Xiaomi\\ MiMo\\ Token\\ Plan\\ \\(China\\)"* ]] || {
    echo "bash completion did not escape spaced provider name" >&2
    printf 'output was: %s\n' "$output" >&2
    return 1
  }
}

test_bash_completion_completes_directories_for_second_arg() {
  local project_dir="$TMPDIR_ROOT/project-dir"
  mkdir -p "$project_dir"
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" bash -c '
    source "$1"
    COMP_WORDS=(ccs BUZZ "$2/pro")
    COMP_CWORD=2
    _ccs_bash_completion
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$ROOT/completions/ccs.bash" "$TMPDIR_ROOT")"
  [[ "$output" == *"$project_dir"* ]] || { echo "bash completion did not include directory" >&2; return 1; }
}

test_install_supports_zsh_and_bash_targets() {
  local install_home="$TMPDIR_ROOT/install-home"
  mkdir -p "$install_home"

  HOME="$install_home" "$ROOT/install.sh" --shell zsh >/tmp/ccs-install-zsh.out
  [[ -x "$install_home/.local/bin/ccs" ]] || { echo "zsh install did not install ccs" >&2; return 1; }
  [[ -f "$install_home/.zsh/completions/_ccs" ]] || { echo "zsh completion not installed" >&2; return 1; }
  grep -q 'ccswitch-cli-companion zsh completion' "$install_home/.zshrc" || { echo "zshrc block missing" >&2; return 1; }

  HOME="$install_home" "$ROOT/install.sh" --shell bash >/tmp/ccs-install-bash.out
  [[ -f "$install_home/.local/share/bash-completion/completions/ccs" ]] || { echo "bash completion not installed" >&2; return 1; }
  grep -q 'ccswitch-cli-companion bash completion' "$install_home/.bashrc" || { echo "bashrc block missing" >&2; return 1; }
}

test_install_can_skip_completion() {
  local install_home="$TMPDIR_ROOT/install-no-completion-home"
  mkdir -p "$install_home"

  HOME="$install_home" "$ROOT/install.sh" --no-completion >/tmp/ccs-install-none.out
  [[ -x "$install_home/.local/bin/ccs" ]] || { echo "no-completion install did not install ccs" >&2; return 1; }
  [[ ! -e "$install_home/.zsh/completions/_ccs" ]] || { echo "zsh completion should not be installed" >&2; return 1; }
  [[ ! -e "$install_home/.local/share/bash-completion/completions/ccs" ]] || { echo "bash completion should not be installed" >&2; return 1; }
}

test_install_removes_legacy_zsh_completion_block() {
  local install_home="$TMPDIR_ROOT/install-legacy-home"
  mkdir -p "$install_home"
  cat > "$install_home/.zshrc" <<'EOF'
# before
# ccswitch-cli-companion completion
export PATH="$HOME/.local/bin:$PATH"
fpath=("$HOME/.zsh/completions" $fpath)
autoload -Uz compinit
compinit -i
# end ccswitch-cli-companion completion
# after
EOF

  HOME="$install_home" "$ROOT/install.sh" --shell zsh >/tmp/ccs-install-legacy.out
  ! grep -q '# ccswitch-cli-companion completion' "$install_home/.zshrc" || { echo "legacy zsh block was not removed" >&2; return 1; }
  grep -q '# ccswitch-cli-companion zsh completion' "$install_home/.zshrc" || { echo "new zsh block missing" >&2; return 1; }
  grep -q '# before' "$install_home/.zshrc" || { echo "content before legacy block was removed" >&2; return 1; }
  grep -q '# after' "$install_home/.zshrc" || { echo "content after legacy block was removed" >&2; return 1; }
}

test_no_token_in_list_output() {
  local output
  output="$(run_with_home ccs)"
  [[ "$output" != *"secret-buzz"* ]] || { echo "list leaked token" >&2; return 1; }
  [[ "$output" != *"secret-pixel"* ]] || { echo "list leaked token" >&2; return 1; }
}

main() {
  test_no_args_lists_providers
  test_provider_launch_writes_settings_and_calls_claude
  test_completion_rows_include_provider_metadata
  test_bash_completion_completes_provider_names
  test_bash_completion_escapes_provider_names_with_spaces
  test_bash_completion_completes_directories_for_second_arg
  test_install_supports_zsh_and_bash_targets
  test_install_can_skip_completion
  test_install_removes_legacy_zsh_completion_block
  test_no_token_in_list_output
  echo "All tests passed"
}

main "$@"
