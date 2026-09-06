#!/data/data/com.termux/files/usr/bin/bash
# Assembles a nightly-2026-08-08 Rust toolchain (glibc host) for Termux.
# Result: ~/nightly/toolchain + ~/nightly/bin/n-cargo + ~/proot-glibc/lib2
set -euo pipefail

DIST_DATE=2026-08-08
BASE="https://static.rust-lang.org/dist/$DIST_DATE"
PREFIX="$HOME/nightly/toolchain"
WORK="$HOME/nightly/dl"

mkdir -p "$PREFIX/bin" "$PREFIX/lib/rustlib" "$WORK" "$HOME/tmp"

download() {
  local name="$1"
  if [ ! -f "$WORK/$name.tar.xz" ]; then
    echo ">> downloading $name"
    curl -fsSL --retry 3 "$BASE/$name.tar.xz" -o "$WORK/$name.tar.xz"
  fi
  ( cd "$WORK" && tar -xJf "$name.tar.xz" 2>/dev/null || true )
}

# 1) rustc (component 'rust') — host glibc
download "rust-nightly-aarch64-unknown-linux-gnu"
D="$WORK/rust-nightly-aarch64-unknown-linux-gnu"
cp "$D/rustc/bin/rustc" "$PREFIX/bin/rustc"
cp "$D/rustc/bin/rustdoc" "$PREFIX/bin/rustdoc"
cp -r "$D/rustc/lib/." "$PREFIX/lib/"

# 2) cargo
download "cargo-nightly-aarch64-unknown-linux-gnu"
cp "$WORK/cargo-nightly-aarch64-unknown-linux-gnu/cargo/bin/cargo" "$PREFIX/bin/cargo"

# 3) rust-std for the android target
download "rust-std-nightly-aarch64-linux-android"
cp -r "$WORK/rust-std-nightly-aarch64-linux-android/rust-std-aarch64-linux-android/lib/rustlib/aarch64-linux-android" \
      "$PREFIX/lib/rustlib/"

# 4) rust-std for the gnu host (needed for host build scripts)
download "rust-std-nightly-aarch64-unknown-linux-gnu"
cp -r "$WORK/rust-std-nightly-aarch64-unknown-linux-gnu/rust-std-aarch64-unknown-linux-gnu/lib/rustlib/aarch64-unknown-linux-gnu" \
      "$PREFIX/lib/rustlib/"

chmod +x "$PREFIX/bin/"*

# 5) /lib stub for proot: symlink copy of the glibc lib dir, with a valid ELF libc.so
GLIBC_LIB="/data/data/com.termux/files/usr/glibc/lib"
LIB2="$HOME/proot-glibc/lib2"
rm -rf "$LIB2"; mkdir -p "$LIB2"
for f in "$GLIBC_LIB"/*; do ln -sf "$f" "$LIB2/"; done
rm -f "$LIB2/libc.so"
ln -s "$GLIBC_LIB/libc.so.6" "$LIB2/libc.so"

# bfd ld wrappers (first in PATH inside proot so gcc's collect2 doesn't pick Termux lld)
BIN="$HOME/proot-glibc/bin"
mkdir -p "$BIN"
for t in ld ld.bfd as; do
  [ -e "/data/data/com.termux/files/usr/glibc/bin/$t" ] && ln -sf "/data/data/com.termux/files/usr/glibc/bin/$t" "$BIN/$t"
done

# 6) n-cargo wrapper
mkdir -p "$HOME/nightly/bin"
cat > "$HOME/nightly/bin/n-cargo" <<'WRAP'
#!/data/data/com.termux/files/usr/bin/bash
unset LD_PRELOAD
export CARGO_HOME=$HOME/.cargo
export TMPDIR=$HOME/tmp
export PATH=$HOME/proot-glibc/bin:/data/data/com.termux/files/usr/glibc/bin:$PATH
export RUSTC=$HOME/nightly/toolchain/bin/rustc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=/data/data/com.termux/files/usr/glibc/bin/gcc
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=/data/data/com.termux/files/usr/bin/clang
export SSL_CERT_FILE=/data/data/com.termux/files/usr/glibc/etc/ssl/certs/ca-certificates.crt
exec proot -b $HOME/proot-glibc/lib2:/lib $HOME/nightly/toolchain/bin/cargo "$@"
WRAP
chmod +x "$HOME/nightly/bin/n-cargo"

echo ">> toolchain ready:"
"$PREFIX/bin/rustc" --version 2>/dev/null || echo "(rustc runs under proot only; test: ~/nightly/bin/n-cargo --version)"
"$HOME/nightly/bin/n-cargo" --version
