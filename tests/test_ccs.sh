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
  ('codex-official', 'codex', 'OpenAI Official', '{"auth":{},"config":""}', 1, 0),
  ('codex-custom', 'codex', 'My Custom API', '{"auth":{"OPENAI_API_KEY":"sk-test123"},"config":"model_provider = \"custom\"\nmodel = \"gpt-4o\"\n\n[model_providers.custom]\nname = \"MyAPI\"\nbase_url = \"https://api.example.com/v1\"\nwire_api = \"responses\"\nrequires_openai_auth = true"}', 2, 1);
SQL

run_with_home() {
  HOME="$HOME_DIR" "$@"
}

# ── Claude tests ──

test_no_args_lists_claude_providers() {
  local output
  output="$(run_with_home ccs)"
  [[ "$output" == *"BUZZ"* ]] || { echo "expected BUZZ in list" >&2; return 1; }
  [[ "$output" == *"ai-pixel"* ]] || { echo "expected ai-pixel in list" >&2; return 1; }
  [[ "$output" != *"Not Claude"* ]] || { echo "should not list non-Claude provider" >&2; return 1; }
  [[ "$output" != *"My Custom API"* ]] || { echo "should not list Codex provider in default list" >&2; return 1; }
}

test_claude_subcommand_lists_providers() {
  local output
  output="$(run_with_home ccs claude)"
  [[ "$output" == *"BUZZ"* ]] || { echo "expected BUZZ in claude list" >&2; return 1; }
  [[ "$output" != *"My Custom API"* ]] || { echo "claude list should not include Codex providers" >&2; return 1; }
}

test_claude_launch_writes_settings_and_calls_claude() {
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

test_claude_explicit_launch() {
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
  run_with_home ccs claude BUZZ >/tmp/ccs-test-launch-explicit.out

  grep -q -- '--settings' "$call_file" || { echo "claude was not called with --settings" >&2; return 1; }
  local output
  output="$(cat /tmp/ccs-test-launch-explicit.out)"
  [[ "$output" == *"Using provider: BUZZ (buzz-id)"* ]] || { echo "missing provider launch message (explicit claude)" >&2; return 1; }
}

# ── Codex tests ──

test_codex_subcommand_lists_providers() {
  local output
  output="$(run_with_home ccs codex)"
  [[ "$output" == *"OpenAI Official"* ]] || { echo "expected OpenAI Official in codex list" >&2; return 1; }
  [[ "$output" == *"My Custom API"* ]] || { echo "expected My Custom API in codex list" >&2; return 1; }
  [[ "$output" != *"BUZZ"* ]] || { echo "codex list should not include Claude providers" >&2; return 1; }
}

test_codex_launch_writes_config_and_calls_codex() {
  local stub_dir call_file home_file
  stub_dir="$TMPDIR_ROOT/codex-stub-bin"
  call_file="$TMPDIR_ROOT/codex-call.txt"
  home_file="$TMPDIR_ROOT/codex-home.txt"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CCS_TEST_CALL_FILE"
printf '%s\n' "$CODEX_HOME" > "$CCS_TEST_HOME_FILE"
# Check that auth.json and config.toml exist in CODEX_HOME
if [[ ! -f "$CODEX_HOME/auth.json" ]]; then
  echo "auth.json missing in CODEX_HOME" >&2
  exit 2
fi
if [[ ! -f "$CODEX_HOME/config.toml" ]]; then
  echo "config.toml missing in CODEX_HOME" >&2
  exit 3
fi
SH
  chmod +x "$stub_dir/codex"

  PATH="$stub_dir:$PATH" \
  CCS_TEST_CALL_FILE="$call_file" \
  CCS_TEST_HOME_FILE="$home_file" \
  run_with_home ccs codex "My Custom API" >/tmp/ccs-test-codex-launch.out

  local codex_home
  codex_home="$(cat "$home_file")"
  [[ -n "$codex_home" ]] || { echo "CODEX_HOME was empty" >&2; return 1; }
  [[ ! -d "$codex_home" ]] || { echo "temporary CODEX_HOME directory was not removed" >&2; return 1; }

  local output
  output="$(cat /tmp/ccs-test-codex-launch.out)"
  [[ "$output" == *"Using provider: My Custom API (codex-custom)"* ]] || { echo "missing codex provider launch message" >&2; return 1; }
}

test_codex_launch_official_provider() {
  local stub_dir call_file home_file
  stub_dir="$TMPDIR_ROOT/codex-stub-bin2"
  call_file="$TMPDIR_ROOT/codex-call2.txt"
  home_file="$TMPDIR_ROOT/codex-home2.txt"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CCS_TEST_CALL_FILE"
printf '%s\n' "$CODEX_HOME" > "$CCS_TEST_HOME_FILE"
if [[ ! -f "$CODEX_HOME/auth.json" ]]; then
  echo "auth.json missing in CODEX_HOME" >&2
  exit 2
fi
if [[ ! -f "$CODEX_HOME/config.toml" ]]; then
  echo "config.toml missing in CODEX_HOME" >&2
  exit 3
fi
SH
  chmod +x "$stub_dir/codex"

  PATH="$stub_dir:$PATH" \
  CCS_TEST_CALL_FILE="$call_file" \
  CCS_TEST_HOME_FILE="$home_file" \
  run_with_home ccs codex "OpenAI Official" >/tmp/ccs-test-codex-official.out

  local output
  output="$(cat /tmp/ccs-test-codex-official.out)"
  [[ "$output" == *"Using provider: OpenAI Official (codex-official)"* ]] || { echo "missing official codex provider launch message" >&2; return 1; }
}

# ── Completion tests ──

test_completion_rows_include_claude_provider_metadata() {
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" zsh -fc 'source "$1" --rows claude' _ "$ROOT/completions/_ccs")"
  [[ "$output" == *$'BUZZ\t-'* ]] || { echo "completion rows missing BUZZ" >&2; return 1; }
  [[ "$output" == *"https://buzz.example/v1"* ]] || { echo "completion rows missing base url" >&2; return 1; }
}

test_completion_rows_include_codex_providers() {
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" zsh -fc 'source "$1" --rows codex' _ "$ROOT/completions/_ccs")"
  [[ "$output" == *"OpenAI Official"* ]] || { echo "completion rows missing OpenAI Official" >&2; return 1; }
  [[ "$output" == *"My Custom API"* ]] || { echo "completion rows missing My Custom API" >&2; return 1; }
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

test_bash_completion_completes_app_types() {
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" bash -c '
    source "$1"
    COMP_WORDS=(ccs co)
    COMP_CWORD=1
    _ccs_bash_completion
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$ROOT/completions/ccs.bash")"
  [[ "$output" == *"codex"* ]] || { echo "bash completion did not include codex app type" >&2; return 1; }
}

test_bash_completion_completes_codex_providers() {
  local output
  output="$(PATH="$ROOT/bin:$PATH" HOME="$HOME_DIR" bash -c '
    source "$1"
    COMP_WORDS=(ccs codex My)
    COMP_CWORD=2
    _ccs_bash_completion
    printf "%s\n" "${COMPREPLY[@]}"
  ' _ "$ROOT/completions/ccs.bash")"
  [[ "$output" == *"My\\"*"Custom"* ]] || { echo "bash completion did not include My Custom API for codex" >&2; printf 'output was: %s\n' "$output" >&2; return 1; }
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

# ── Install tests ──

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

# ── Security tests ──

test_no_token_in_claude_list_output() {
  local output
  output="$(run_with_home ccs)"
  [[ "$output" != *"secret-buzz"* ]] || { echo "claude list leaked token" >&2; return 1; }
  [[ "$output" != *"secret-pixel"* ]] || { echo "claude list leaked token" >&2; return 1; }
}

test_no_token_in_codex_list_output() {
  local output
  output="$(run_with_home ccs codex)"
  [[ "$output" != *"sk-test123"* ]] || { echo "codex list leaked API key" >&2; return 1; }
}

main() {
  # Claude tests
  test_no_args_lists_claude_providers
  test_claude_subcommand_lists_providers
  test_claude_launch_writes_settings_and_calls_claude
  test_claude_explicit_launch

  # Codex tests
  test_codex_subcommand_lists_providers
  test_codex_launch_writes_config_and_calls_codex
  test_codex_launch_official_provider

  # Completion tests
  test_completion_rows_include_claude_provider_metadata
  test_completion_rows_include_codex_providers
  test_bash_completion_completes_provider_names
  test_bash_completion_completes_app_types
  test_bash_completion_completes_codex_providers
  test_bash_completion_escapes_provider_names_with_spaces

  # Install tests
  test_install_supports_zsh_and_bash_targets
  test_install_can_skip_completion
  test_install_removes_legacy_zsh_completion_block

  # Security tests
  test_no_token_in_claude_list_output
  test_no_token_in_codex_list_output

  echo "All tests passed"
}

main "$@"