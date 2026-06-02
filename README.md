# ccswitch-cli-companion

A CLI companion for CC Switch that launches Claude Code with CC Switch provider profiles from your terminal.

`ccs` reads Claude providers from `~/.cc-switch/cc-switch.db`, creates a temporary Claude Code settings file with that provider's environment, then runs:

```bash
claude --settings <temporary-settings-file>
```

This mirrors CC Switch's "Open Terminal" behavior without opening the GUI.

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

## Usage

List Claude providers:

```bash
ccs
```

Launch by provider name or id:

```bash
ccs BUZZ
ccs ai-pixel
ccs 0711c34d-45e0-45a1-9882-8a7b144f0beb
```

Launch in a specific working directory:

```bash
ccs BUZZ /Volumes/workspace/bio/HyperSD
```

If multiple providers share the same name, `ccs` uses `fzf` when available so you can choose with arrow keys. Without `fzf`, it falls back to a numbered prompt.

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
ccs b<Tab>
```

completes provider names. The second argument completes directories:

```bash
ccs BUZZ <Tab>
```

zsh completion shows provider metadata in descriptions. Bash completion completes provider names and directories.

## Requirements

- macOS or Linux
- Bash 3.2+ for the CLI
- `sqlite3`
- `python3`
- Claude Code CLI: `claude`
- Optional: `fzf` for duplicate-name selection
- Optional: zsh or bash completion support

## Security notes

`ccs` does not print tokens. It writes provider env into a temporary settings file, then removes that file when Claude Code exits.

The temporary settings file exists while `claude` is running, matching CC Switch's GUI launcher behavior.
