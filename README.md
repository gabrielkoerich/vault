# vault

Temporarily lock down sensitive files on your machine. One command to encrypt everything, one to bring it back.

```
$ vault lockdown
locking 12 sensitive path(s):
  ~/.ssh
  ~/.gnupg
  ~/.private
  ~/Projects/app/.env
  ...

enter a passphrase to encrypt the vault:
locked. sensitive files encrypted to ~/.vault.tar.age

$ vault unlock
enter your passphrase to decrypt the vault:
unlocked. all sensitive files restored
```

## Why

Sensitive files sitting on disk are an attack surface. Someone or something could:
- Run a malicious `postinstall` script that exfiltrates keys
- Glance at your terminal while you `cat` a config file
- Run `find ~ -name .env` if they get a moment on your machine
- Exploit a dependency to read `~/.ssh` or `~/.gnupg`

Vault removes the surface entirely. No files on disk means nothing to steal. Useful before screen shares, pair programming, interviews, live coding, running untrusted code, or just to feel safer.

## Install

```bash
brew tap gabrielkoerich/tap
brew install vault
```

Or just copy the `vault` script somewhere in your `$PATH`.

### Dependencies

- [age](https://github.com/FiloSottile/age) — encryption
- [fd](https://github.com/sharkdp/fd) — fast file finder
- [ripgrep](https://github.com/BurntSushi/ripgrep) — fast content search
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
# SSH keys
$HOME/.ssh

# GPG keys
$HOME/.gnupg

# Private credentials
$HOME/.private

# Encryption keys
$HOME/.config/age
```

### `scan.yml`

Controls what `vault scan` looks for. On first run, a default `scan.yml` is copied to `~/.config/vault/scan.yml` — edit it to add or remove paths.

```yaml
# SSH & GPG keys
- $HOME/.ssh
- $HOME/.gnupg

# Cloud & infrastructure
- $HOME/.aws
- $HOME/.kube/config
- $HOME/.cloudflared

# Dev tool tokens
- $HOME/.npmrc
- $HOME/.netrc
- $HOME/.docker/config.json
- $HOME/.config/gh/hosts.yml

# AI tools
- $HOME/.codex
- $HOME/.config/claude

# Databases
- $HOME/.pgpass
- $HOME/.my.cnf

# Shell history
- $HOME/.zsh_history
- $HOME/.bash_history
```

See the full default list in [`scan.yml`](scan.yml).

`vault scan` also automatically finds `.env` files under `$HOME`, scans shell config files for exported secrets (`API_KEY`, `TOKEN`, `PASSWORD`, etc.), and searches `~/.config` for private key files.

During `vault lockdown`, any `.env` files found under `$HOME` are included after a prompt.

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

## Ideas

- **Profiles** — named lockdown profiles (`vault lockdown --profile work`) for different contexts
- **Hooks** — run custom scripts before/after lockdown and unlock
- **Lock screen integration** — lock the screen on `vault lockdown`, or trigger lockdown when the screen locks

## Related projects

Vault is specifically about temporarily removing secrets from disk. These projects solve related but different problems:

- [Cryptomator](https://github.com/cryptomator/cryptomator) — encrypted vaults for cloud storage (GUI, always-on encryption)
- [gocryptfs](https://github.com/rfjakob/gocryptfs) — encrypted overlay filesystem via FUSE (mount/unmount encrypted directories)
- [git-crypt](https://github.com/AGWA/git-crypt) — transparent file encryption in git repos
- [git-secret](https://github.com/sobolevn/git-secret) — store secrets in git using GPG
- [SOPS](https://github.com/getsops/sops) — encrypted file editor for config and secrets (supports age, GPG, cloud KMS)
- [pass](https://www.passwordstore.org/) — Unix password manager using GPG (stores passwords, not arbitrary files)
- [Tomb](https://github.com/dyne/Tomb) — encrypted storage folders on Linux using LUKS

## License

MIT
