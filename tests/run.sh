#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="$ROOT/vault"

tmp="$(mktemp -d)"
cleanup() {
  case "${VAULT_KEYCHAIN:-}" in
    "$tmp"/*)
      [ -f "$VAULT_KEYCHAIN" ] && security delete-keychain "$VAULT_KEYCHAIN" 2>/dev/null || true
      ;;
  esac
  rm -rf "$tmp"
}
trap cleanup EXIT

export HOME="$tmp/home"
export VAULT_CONFIG_DIR="$tmp/config"
export VAULT_FILE="$tmp/vault.tar.age"
export VAULTS_DIR="$tmp/vaults"
export KEYCHAIN_PREFIX="gabrielkoerich/vault-test-$RANDOM"
export KEYCHAIN_DELETE_CONFIRM="no"
export VAULT_NO_ENV_SCAN="1"

mkdir -p "$HOME" "$VAULT_CONFIG_DIR"

# security resolves the default keychain through $HOME, which the tests fake.
# Without a keychain of our own it shows a modal dialog and hangs on CI.
export VAULT_IDENTITY_KIND=plain
unset VAULT_KEYCHAIN   # never inherit a real keychain from the environment
if [ "$(uname)" = "Darwin" ] && command -v security >/dev/null 2>&1; then
  export VAULT_KEYCHAIN="$tmp/test.keychain-db"
  security create-keychain -p "" "$VAULT_KEYCHAIN"
  security unlock-keychain -p "" "$VAULT_KEYCHAIN"
fi
printf 'DELETE_METHOD=rm\nENV_SCAN_DIRS=%s\nEXCLUDE_PATHS=\n' "$HOME" > "$VAULT_CONFIG_DIR/settings"

case "$HOME" in
  "$tmp"/*) : ;;
  *) echo "refusing to run: HOME is not in temp dir" >&2; exit 1 ;;
esac
case "$VAULT_CONFIG_DIR" in
  "$tmp"/*) : ;;
  *) echo "refusing to run: VAULT_CONFIG_DIR is not in temp dir" >&2; exit 1 ;;
esac
case "$VAULTS_DIR" in
  "$tmp"/*) : ;;
  *) echo "refusing to run: VAULTS_DIR is not in temp dir" >&2; exit 1 ;;
esac
case "$VAULT_FILE" in
  "$tmp"/*) : ;;
  *) echo "refusing to run: VAULT_FILE is not in temp dir" >&2; exit 1 ;;
esac
if [ -n "${VAULT_KEYCHAIN:-}" ]; then
  case "$VAULT_KEYCHAIN" in
    "$tmp"/*) : ;;
    *) echo "refusing to run: VAULT_KEYCHAIN is not in temp dir" >&2; exit 1 ;;
  esac
fi

expect_fail() {
  if "$@"; then
    echo "expected failure but command succeeded: $*" >&2
    exit 1
  fi
}

# True only when /dev/tty can actually be opened (real interactive terminal).
# [ -c /dev/tty ] only checks the device exists, not that it's usable.
can_use_tty() {
  { exec 3</dev/tty && exec 3>&-; } 2>/dev/null
}

echo "secret" > "$HOME/secret.txt"
printf '%s\n' "$HOME/secret.txt" > "$VAULT_CONFIG_DIR/paths"

# Generate key and extract public key
age-keygen -o "$tmp/ci.key" 2> "$tmp/keygen.out"
pubkey="$(awk '/Public key:/ {print $3}' "$tmp/keygen.out")"
# Ensure the key file is fully written before we continue
sync

echo "$pubkey" > "$tmp/recipients.txt"

# --- recipient / default-vault tests (CI-safe) ---
"$VAULT" lockdown --recipients-file "$tmp/recipients.txt"
test -f "$VAULT_FILE"
test ! -e "$HOME/secret.txt"

"$VAULT" status >/dev/null

"$VAULT" unlock --identity-file "$tmp/ci.key" --keep-keychain
test -f "$HOME/secret.txt"
grep -q "secret" "$HOME/secret.txt"

"$VAULT" status >/dev/null
echo "ok - recipient / default-vault tests"

# --- named vault tests (CI-safe) ---
echo "named" > "$HOME/named.txt"
"$VAULT" create named --recipients-file "$tmp/recipients.txt" "$HOME/named.txt"
test -f "$VAULTS_DIR/named.tar.age"
test ! -e "$HOME/named.txt"
"$VAULT" open named --identity-file "$tmp/ci.key" --keep-keychain
test -f "$HOME/named.txt"
grep -q "named" "$HOME/named.txt"
echo "ok - named vault tests"

# --- named vault with identity-stdin (CI-safe) ---
echo "recipient" > "$HOME/rec.txt"
"$VAULT" create rec --recipients-file "$tmp/recipients.txt" "$HOME/rec.txt"
test -f "$VAULTS_DIR/rec.tar.age"
test ! -e "$HOME/rec.txt"
cat "$tmp/ci.key" | "$VAULT" open rec --identity-stdin
test -f "$HOME/rec.txt"
grep -q "recipient" "$HOME/rec.txt"
echo "ok - named vault with identity-stdin"

# --- install script (CI-safe) ---
PREFIX="$tmp/prefix" "$ROOT/install.sh"
test -x "$tmp/prefix/bin/vault"
echo "ok - install script"

# --- error cases (CI-safe) ---
expect_fail "$VAULT" open rec --identity-file "$tmp/missing.key"
expect_fail "$VAULT" create rec2 --recipients-file "$tmp/missing.recipients" "$HOME/rec.txt"
echo "ok - error cases"

# --- keychain identity mode (no terminal needed) ---
if [ -n "${VAULT_KEYCHAIN:-}" ]; then
  echo "idv" > "$HOME/idv.txt"
  "$VAULT" create idv "$HOME/idv.txt"
  test -f "$VAULTS_DIR/idv.tar.age"
  test ! -e "$HOME/idv.txt"
  "$VAULT" open idv
  test -f "$HOME/idv.txt"
  grep -q "idv" "$HOME/idv.txt"
  echo "ok - keychain identity round trip"

  # a missing keychain must fail fast rather than block on a dialog
  (
    unset VAULT_KEYCHAIN
    export HOME="$tmp/nokeychain"
    mkdir -p "$HOME"
    echo "x" > "$HOME/x.txt"
    expect_fail "$VAULT" create nokc "$HOME/x.txt"
  )
  echo "ok - missing keychain fails fast"
fi

# --- removed passphrase flags are rejected, not silently ignored ---
echo "rej" > "$HOME/rej.txt"
expect_fail "$VAULT" create rej --passphrase "x" "$HOME/rej.txt"
expect_fail "$VAULT" create rej --generate-pass "$HOME/rej.txt"
test -e "$HOME/rej.txt"
echo "ok - passphrase flags rejected"

echo "ok"
