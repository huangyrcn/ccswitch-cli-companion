# ccswitch-cli-companion

A CLI companion for CC Switch that launches Claude Code with CC Switch provider profiles from your terminal.

`ccs` reads Claude providers from `~/.cc-switch/cc-switch.db`, creates a temporary Claude Code settings file with that provider's environment, then runs:

```bash
claude --settings <temporary-settings-file>
```

This mirrors CC Switch's "Open Terminal" behavior without opening the GUI.

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
source ~/.zshrc
```

The installer copies:

- `bin/ccs` to `~/.local/bin/ccs`
- `completions/_ccs` to `~/.zsh/completions/_ccs`

and ensures your `~/.zshrc` loads the completion directory.

## Completion

After install and `source ~/.zshrc`:

```bash
ccs b<Tab>
```

completes provider names. The second argument completes directories:

```bash
ccs BUZZ <Tab>
```

## Requirements

- macOS or Linux shell environment
- `zsh` for completion
- `sqlite3`
- `python3`
- Claude Code CLI: `claude`
- Optional: `fzf` for duplicate-name selection

## Security notes

`ccs` does not print tokens. It writes provider env into a temporary settings file, then removes that file when Claude Code exits.

The temporary settings file exists while `claude` is running, matching CC Switch's GUI launcher behavior.
