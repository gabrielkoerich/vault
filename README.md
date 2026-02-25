# Vault

[![CI](https://github.com/gabrielkoerich/vault/actions/workflows/release.yml/badge.svg)](https://github.com/gabrielkoerich/vault/actions/workflows/release.yml)

Temporarily lock down sensitive files on your machine. One command to encrypt everything, one to bring it back.

## Why?

Sensitive files sitting on disk are an attack surface. Someone or something could:
- Run a malicious `postinstall` script that exfiltrates keys
- Clone a repository with a fake dependency which tries to steal your data
- Glance at your terminal while you `cat` a config file
- Run `find ~ -name .env` if they get a moment on your machine
- Exploit a dependency to read `~/.ssh` or `~/.gnupg`

Vault removes the surface entirely. No files on disk means nothing to steal. Useful before screen shares, pair programming, interviews, live coding, running untrusted code, or just to feel safer.

## How it works

1. **lockdown** reads paths from `~/.config/vault/paths`, optionally scans for `.env` files under `$HOME`, bundles everything into a tar archive, encrypts it with a passphrase using `age -p`, then removes the originals.
2. **unlock** decrypts the archive with your passphrase and extracts everything back to the original locations.

The vault file lives at `~/.vault.tar.age`. A manifest at `~/.vault-manifest` tracks what was locked (useful for `vault status`).

Passphrase encryption means no keys need to exist on disk — the only secret is in your head.

> ⚠️ *If you lose your passphrase, you will lose access to all locked files.*

## Quickstart

```bash
brew tap gabrielkoerich/tap
brew install vault
vault init
```

Or just copy the `vault` script somewhere in your `$PATH` and run `vault init`.

```bash
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

## Usage

```bash
vault init                    # setup config and scan for sensitive files
vault lockdown                # encrypt and remove sensitive files
vault unlock [--keep-keychain]  # restore from encrypted vault
vault create <name> <paths>   # create a named vault from explicit paths
vault open <name> [--keep-keychain] # restore a named vault
vault scan                    # re-scan and update paths
vault status                  # show locked/unlocked state
vault paths                   # list configured paths
vault version                 # show version
```

### Dependencies

- [age](https://github.com/FiloSottile/age) — encryption
- [fd](https://github.com/sharkdp/fd) — fast file finder
- [ripgrep](https://github.com/BurntSushi/ripgrep) — fast content search
- `tar` — bundling (ships with macOS/Linux)

Optional: `trash` (macOS) for recoverable deletion instead of `rm`.

## Configuration

Vault reads from `~/.config/vault/`:

### `paths`

One sensitive path per line. Supports `$HOME` expansion. Lines starting with `#` are ignored.

```bash
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

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_CONFIG_DIR` | `~/.config/vault` | Config directory |
| `VAULT_FILE` | `~/.vault.tar.age` | Encrypted vault path |
| `VAULTS_DIR` | `~/.vaults` | Directory for named vault files |
| `KEYCHAIN_PREFIX` | `gabrielkoerich/vault` | macOS Keychain service prefix |
| `KEYCHAIN_DELETE_CONFIRM` | `yes` | prompt before deleting Keychain entries |
| `VAULT_RECIPIENTS_FILE` | (unset) | age recipients file (recipient mode) |
| `VAULT_IDENTITY_FILE` | (unset) | age identity file (recipient mode) |
| `VAULT_NO_ENV_SCAN` | `0` | skip `.env` scan prompt during lockdown |

## Keychain (default)

On macOS, Vault stores passphrases in Keychain by default and retrieves them on `lockdown/open`. If no entry exists, Vault prompts you and saves it.

Keychain entries are deleted after a vault is opened, with a confirmation prompt to avoid stale secrets.

Use `--keep-keychain` on `unlock`/`open` to skip deletion.

## Recipient Mode (CI / Production)

Recipient mode uses **public‑key encryption** instead of a shared passphrase.
You encrypt to one or more **recipients** (public keys). Only the matching **identity**
(private key) can decrypt. This is ideal for CI/production because you can commit encrypted
files to git while keeping the private key only in CI secrets. Recipient mode bypasses
Keychain entirely.

> **Note on terminology:** Vault uses age's standard terms — a **recipient** is a public key
> you encrypt to, and an **identity** is the corresponding private key used to decrypt.
> This matches the [age CLI](https://github.com/FiloSottile/age) (`age -r recipient`, `age -i identity`).

Generate a keypair:

```bash
age-keygen -o ci.key
```

The public key is printed on stdout. Use it as a recipient and keep it in the repo (safe to share).
Keep the private key secret (`ci.key`).

Encrypt with a recipient (no Keychain involved):

```bash
vault create secrets --recipient "age1..." ~/.config/secrets
```

Or use a recipients file (one per line):

```bash
vault create secrets --recipients-file recipients.txt ~/.config/secrets
```

Decrypt in CI using the private key (stored as a CI secret):

```bash
printf '%s' "$AGE_SECRET_KEY" | vault open secrets --identity-stdin
```

You can also set:

```bash
export VAULT_RECIPIENTS_FILE=recipients.txt
export VAULT_IDENTITY_FILE=ci.key
```

### Example: Git + GitHub Actions

1. Generate the keypair once (locally):

```bash
age-keygen -o ci.key
```

2. Save the private key as a GitHub Actions secret (e.g. `AGE_SECRET_KEY`).
3. Commit the public key (printed by `age-keygen`) to the repo in `recipients.txt`.
4. Encrypt and commit your secrets:

```bash
vault create secrets --recipients-file recipients.txt ~/.config/secrets
git add ~/.vaults/secrets.tar.age
git commit -m "Add encrypted solana vault"
```

5. Decrypt in CI:

```bash
printf '%s' "$AGE_SECRET_KEY" | vault open secrets --identity-stdin
```

### Key management tips

- Keep private keys only in your password manager or CI secrets.
- You can add multiple recipients (one per line in `recipients.txt`) for shared access.
- Rotate keys by adding a new recipient, re‑encrypting, then removing the old recipient.

## Named vaults

Create one-off vaults without touching the global config:

```bash
vault create solana ~/.config/solana ~/.config/solana/id.json
vault open solana
```

For non-interactive use, you can pass the passphrase via stdin (still saved to Keychain on macOS):

```bash
printf '%s' "$VAULT_PASSPHRASE" | vault create solana --passphrase-stdin ~/.config/solana
printf '%s' "$VAULT_PASSPHRASE" | vault open solana --passphrase-stdin
```

`--pass` is a short alias for `--passphrase`.

You can auto‑generate a passphrase (works with `lockdown` and `create`):

```bash
vault create secrets --generate-pass ~/.config/secrets
vault lockdown --generate-pass
```

## Install Without Homebrew

```bash
./install.sh
```

## Ideas/Roadmap

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
