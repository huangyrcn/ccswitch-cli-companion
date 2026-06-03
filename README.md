# ccswitch-cli-companion

A CLI companion for CC Switch that launches Claude Code or Codex with CC Switch provider profiles from your terminal.

## Usage

List Claude providers (default):

```bash
ccs
```

Launch a Claude provider by name or id:

```bash
ccs BUZZ
ccs claude BUZZ
```

List Codex providers:

```bash
ccs codex
```

Launch a Codex provider:

```bash
ccs codex ai-pixel
```

If multiple providers share the same name, `ccs` uses `fzf` when available so you can choose with arrow keys. Without `fzf`, it falls back to a numbered prompt.

## How it works

**Claude** — reads `settings_config.env` from the provider, creates a temporary JSON settings file, and runs:

```bash
claude --settings <temporary-settings-file>
```

The temporary file is removed when Claude Code exits.

**Codex** — reads `settings_config.auth` and `settings_config.config` from the provider, creates a temporary directory with `auth.json` and `config.toml`, and runs:

```bash
CODEX_HOME=<temporary-home> codex
```

The temporary directory is removed when Codex exits. This approach doesn't modify your real `~/.codex/` config, so multiple Codex instances with different providers can run in parallel.

## Platform support

Supported shells and platforms:

- macOS + zsh
- macOS + bash
- Linux + zsh
- Linux + bash

The CLI defaults to `~/.cc-switch/cc-switch.db`. If your CC Switch database lives elsewhere, set:

```bash
export CCS_DB=/path/to/cc-switch.db
```

## Install

From this repository:

```bash
./install.sh
```

Install for a specific shell:

```bash
./install.sh --shell zsh
./install.sh --shell bash
./install.sh --shell both
```

Install without completion:

```bash
./install.sh --no-completion
```

Then reload your shell configuration:

```bash
source ~/.zshrc
# or
source ~/.bashrc
```

The installer copies:

- `bin/ccs` to `~/.local/bin/ccs`
- zsh completion to `~/.zsh/completions/_ccs`
- bash completion to `~/.local/share/bash-completion/completions/ccs`

## Completion

After install and shell reload:

```bash
ccs b<Tab>          # completes Claude provider names
ccs codex <Tab>     # completes Codex provider names
ccs claude <Tab>    # completes Claude provider names
```

Zsh completion shows provider metadata in descriptions. Bash completion completes provider names with proper escaping for names containing spaces.

## Requirements

- macOS or Linux
- Bash 3.2+ for the CLI
- `sqlite3`
- `python3`
- Claude Code CLI (`claude`) and/or Codex CLI (`codex`)
- Optional: `fzf` for duplicate-name selection
- Optional: zsh or bash completion support

## Security notes

`ccs` does not print tokens or API keys in list output. It writes provider credentials into temporary files/directories, then removes them when the launched process exits.