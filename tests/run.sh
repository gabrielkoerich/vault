#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="$ROOT/vault"

tmp="$(mktemp -d)"
cleanup() {
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

expect_fail() {
  if "$@"; then
    echo "expected failure but command succeeded: $*" >&2
    exit 1
  fi
}

echo "secret" > "$HOME/secret.txt"
printf '%s\n' "$HOME/secret.txt" > "$VAULT_CONFIG_DIR/paths"

pubkey="$(age-keygen -o "$tmp/ci.key" | awk '/Public key:/ {print $3}')"
echo "$pubkey" > "$tmp/recipients.txt"

"$VAULT" lockdown --recipients-file "$tmp/recipients.txt"
test -f "$VAULT_FILE"
test ! -e "$HOME/secret.txt"

"$VAULT" status | grep -q "locked"

"$VAULT" unlock --identity-file "$tmp/ci.key" --keep-keychain
test -f "$HOME/secret.txt"
grep -q "secret" "$HOME/secret.txt"

"$VAULT" status | grep -q "unlocked"

echo "named" > "$HOME/named.txt"
"$VAULT" create named --recipients-file "$tmp/recipients.txt" "$HOME/named.txt"
test -f "$VAULTS_DIR/named.tar.age"
test ! -e "$HOME/named.txt"
"$VAULT" open named --identity-file "$tmp/ci.key" --keep-keychain
test -f "$HOME/named.txt"
grep -q "named" "$HOME/named.txt"

if { [ -c /dev/tty ] || [ -t 0 ]; } && [ "$(uname)" = "Darwin" ] && command -v security >/dev/null 2>&1; then
  echo "gen" > "$HOME/gen.txt"
  "$VAULT" create gen --generate-pass "$HOME/gen.txt"
  test -f "$VAULTS_DIR/gen.tar.age"
  test ! -e "$HOME/gen.txt"
  "$VAULT" open gen
  test -f "$HOME/gen.txt"
  grep -q "gen" "$HOME/gen.txt"
fi

echo "recipient" > "$HOME/rec.txt"
"$VAULT" create rec --recipients-file "$tmp/recipients.txt" "$HOME/rec.txt"
test -f "$VAULTS_DIR/rec.tar.age"
test ! -e "$HOME/rec.txt"
cat "$tmp/ci.key" | "$VAULT" open rec --identity-stdin
test -f "$HOME/rec.txt"
grep -q "recipient" "$HOME/rec.txt"

PREFIX="$tmp/prefix" "$ROOT/install.sh"
test -x "$tmp/prefix/bin/vault"

if [ -c /dev/tty ] || [ -t 0 ]; then
  passphrase="testpass-123"
  echo "badpass" > "$HOME/badpass.txt"
  "$VAULT" create badpass --passphrase "$passphrase" "$HOME/badpass.txt"
  expect_fail "$VAULT" open badpass --passphrase "wrong"
  test -f "$VAULTS_DIR/badpass.tar.age"
  test ! -e "$HOME/badpass.txt"

  expect_fail "$VAULT" open missing --passphrase "x"
  expect_fail "$VAULT" create missingpath --passphrase "x" "$HOME/does-not-exist"

  echo "dup" > "$HOME/dup.txt"
  "$VAULT" create dup --passphrase "x" "$HOME/dup.txt"
  expect_fail "$VAULT" create dup --passphrase "x" "$HOME/dup.txt"
  cat "$tmp/ci.key" | "$VAULT" open dup --identity-stdin

  echo "mix" > "$HOME/mix.txt"
  expect_fail "$VAULT" create mix --passphrase "x" --recipient "$pubkey" "$HOME/mix.txt"
fi

expect_fail "$VAULT" open rec --identity-file "$tmp/missing.key"
expect_fail "$VAULT" create rec2 --recipients-file "$tmp/missing.recipients" "$HOME/rec.txt"

if { [ -c /dev/tty ] || [ -t 0 ]; } && [ "$(uname)" = "Darwin" ] && command -v security >/dev/null 2>&1; then
  echo "kc" > "$HOME/kc.txt"
  security add-generic-password -a "$USER" -s "${KEYCHAIN_PREFIX}:kc" -w "kcpass" -U >/dev/null
  "$VAULT" create kc "$HOME/kc.txt"
  test -f "$VAULTS_DIR/kc.tar.age"
  test ! -e "$HOME/kc.txt"
  "$VAULT" open kc
  test -f "$HOME/kc.txt"
  expect_fail security find-generic-password -a "$USER" -s "${KEYCHAIN_PREFIX}:kc" >/dev/null
fi

echo "ok"
