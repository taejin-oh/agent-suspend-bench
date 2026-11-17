#!/usr/bin/env bash
# Go 툴체인을 이 폴더 안에 받고, substrate 를 고정 commit 으로 checkout 한다. sudo 불필요.
set -euo pipefail
source "$(dirname "$0")/env.sh"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"; arch="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
if [ ! -x "$ROOT/toolchain/go/bin/go" ]; then
  f="$GO_VERSION.$os-$arch.tar.gz"; mkdir -p "$ROOT/toolchain"; cd "$ROOT/toolchain"
  curl -fsSLO "https://go.dev/dl/$f"
  want="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' | python3 -c "import json,sys; print([x['sha256'] for r in json.load(sys.stdin) if r['version']=='$GO_VERSION' for x in r['files'] if x['filename']=='$f'][0])")"
  got="$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | cut -d' ' -f1)"
  [ "$want" = "$got" ] || { echo "go tarball checksum mismatch"; exit 1; }
  tar xzf "$f"; rm "$f"
fi
go version
if [ ! -d "$SUBSTRATE_DIR/.git" ]; then mkdir -p "$ROOT/src"; git clone -q "$SUBSTRATE_REPO" "$SUBSTRATE_DIR"; fi
git -C "$SUBSTRATE_DIR" fetch -q origin; git -C "$SUBSTRATE_DIR" checkout -q "$SUBSTRATE_COMMIT"
git -C "$SUBSTRATE_DIR" log -1 --format='substrate %H %ad' | tee "$RESULTS/01_substrate_commit.txt"
