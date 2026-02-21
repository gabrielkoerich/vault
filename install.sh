#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${PREFIX}/bin"

mkdir -p "$BIN_DIR"
install -m 0755 vault "$BIN_DIR/vault"

echo "installed vault to $BIN_DIR/vault"
echo "make sure $BIN_DIR is in your PATH"
