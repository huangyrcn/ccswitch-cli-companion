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
  ('codex-id', 'codex', 'Not Claude', '{}', 3, 0);
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
  test_no_token_in_list_output
  echo "All tests passed"
}

main "$@"
