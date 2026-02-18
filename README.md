# vault

Lock down sensitive files before screen sharing, pair programming, or interviews. One command to encrypt everything, one to bring it back.

```
$ vault lockdown
locking 7 sensitive path(s):
  /Users/you/.private
  /Users/you/.ssh
  /Users/you/.config/solana
  /Users/you/.config/age/dotfiles.agekey
  /Users/you/.cloudflared
  /Users/you/.codex/auth.json
  /Users/you/.gnupg/private-keys-v1.d

enter a passphrase to encrypt the vault:
locked. sensitive files encrypted to /Users/you/.vault.tar.age

$ vault unlock
enter your passphrase to decrypt the vault:
unlocked. all sensitive files restored
```

## Why

During calls, interviews, or screen shares, someone could:
- Ask you to clone a repo with malicious `postinstall` scripts
- Glance at your terminal while you `cat` a config file
- Run `find ~ -name .env` if they get a moment on your machine

Vault removes the attack surface entirely. No files on disk means nothing to steal.

## Install

```bash
brew tap gabrielkoerich/tap
brew install vault
```

Or just copy the `vault` script somewhere in your `$PATH`.

### Dependencies

- [age](https://github.com/FiloSottile/age) — encryption (`brew install age`)
- `tar` — bundling (ships with macOS/Linux)

Optional: `trash` (macOS) for recoverable deletion instead of `rm`.

## Usage

```bash
vault lockdown     # encrypt and remove sensitive files
vault unlock       # restore from encrypted vault
vault scan         # auto-detect exposed secrets
vault status       # show locked/unlocked state
vault paths        # list configured paths
vault version      # show version
```

## Configuration

Vault reads from `~/.config/vault/`:

### `paths`

One sensitive path per line. Supports `$HOME` expansion. Lines starting with `#` are ignored.

```
# API keys and credentials
$HOME/.private

# SSH keys and config
$HOME/.ssh

# Crypto wallets
$HOME/.config/solana

# Encryption keys
$HOME/.config/age/dotfiles.agekey
```

### `scan-candidates`

Paths for `vault scan` to check. Format: `type:path` where type is `f` (file), `d` (directory), or `g` (grep pattern in file).

```
f:$HOME/.private
d:$HOME/.ssh
d:$HOME/.config/solana
g:$HOME/.docker/config.json:"auth"
```

`vault scan` also automatically scans shell config files for exported secrets (`API_KEY`, `TOKEN`, `PASSWORD`, etc.) and searches `~/.config` for private key files.

## How it works

1. **lockdown** reads paths from `~/.config/vault/paths`, bundles them into a tar archive, encrypts it with a passphrase using `age -p`, then removes the originals.
2. **unlock** decrypts the archive with your passphrase and extracts everything back to the original locations.

The vault file lives at `~/.vault.tar.age`. A manifest at `~/.vault-manifest` tracks what was locked (useful for `vault status`).

Passphrase encryption means no keys need to exist on disk — the only secret is in your head.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_CONFIG_DIR` | `~/.config/vault` | Config directory |
| `VAULT_FILE` | `~/.vault.tar.age` | Encrypted vault path |

## License

MIT
