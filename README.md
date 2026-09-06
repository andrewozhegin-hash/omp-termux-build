# oh-my-pi (omp) — Native Build for Android / Termux

[oh-my-pi](https://github.com/anatoli-tsinovoy/oh-my-pi) is a Rust-based agentic coding runtime (`omp`) that can be built **natively on your phone** for Android ARM64 (aarch64-linux-android, bionic). This repository contains the complete on-device build recipe — no NDK, no cross-compilation, no root required.

> Built and verified on Termux (Android 14, aarch64, 8 GB RAM): `omp 0.1.0` runs, talks to LLM providers, and the interactive chat with tools works.

## What's here

- `n-cargo` — a cargo wrapper that runs the nightly toolchain under proot
- `build-toolchain.sh` — assembles the nightly-2026-08-08 toolchain from official rust.org tarballs
- `proot-glibc-lib2/` (generated) — a `/lib` stub directory for glibc binaries inside proot
- `models.toml.example` — template for hooking up a custom OpenAI-compatible provider (b.ai, etc.)
- Source patches — branch `omp2-termux-android-arm64-fixes` of the omp fork (see [Patches](#patches))

## Quick start

### 1. Termux dependencies

```bash
pkg update
pkg install rust rust-std-aarch64-linux-android git python clang binutils proot tar xz glibc-repo
pkg install gcc-glibc            # host linker (glibc gcc from termux-glibc repo)
pkg install glibc                 # glibc runtime at /data/data/com.termux/files/usr/glibc
python -m pip install uv          # used by crates/py
```

### 2. Toolchain (rustc 1.99-nightly, 2026-08-08, glibc host)

Termux ships stable Rust only. The omp branch requires `nightly-2026-08-08` (its dependencies use feature gates, e.g. `xutf` needs `portable_simd`). The solution: the official `aarch64-unknown-linux-gnu` host distribution + proot:

```bash
./build-toolchain.sh      # downloads rustc/cargo/std-android/std-gnu, assembles ~/nightly/toolchain
```

What the script does:

1. Downloads from static.rust-lang.org: `rust-nightly-aarch64-unknown-linux-gnu`, `cargo-nightly-aarch64-unknown-linux-gnu`, `rust-std-nightly-aarch64-linux-android`, `rust-std-nightly-aarch64-unknown-linux-gnu`
2. Lays them out into `~/nightly/toolchain` (bin/, lib/, lib/rustlib/…)
3. Creates `~/proot-glibc/lib2` — a symlink copy of `/data/data/com.termux/files/usr/glibc/lib` in which the GNU-ld text script `libc.so` is replaced by a valid ELF symlink `libc.so → libc.so.6`
4. Generates the `~/nightly/bin/n-cargo` wrapper:

```bash
#!/data/data/com.termux/files/usr/bin/bash
unset LD_PRELOAD                            # termux-exec breaks glibc binaries
export CARGO_HOME=$HOME/.cargo
export TMPDIR=$HOME/tmp
export PATH=$HOME/proot-glibc/bin:/data/data/com.termux/files/usr/glibc/bin:$PATH
export RUSTC=$HOME/nightly/toolchain/bin/rustc
# host (aarch64-unknown-linux-gnu) links with glibc gcc; target (android) links with Termux clang:
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=/data/data/com.termux/files/usr/glibc/bin/gcc
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=/data/data/com.termux/files/usr/bin/clang
export SSL_CERT_FILE=/data/data/com.termux/files/usr/glibc/etc/ssl/certs/ca-certificates.crt
exec proot -b $HOME/proot-glibc/lib2:/lib $HOME/nightly/toolchain/bin/cargo "$@"
```

How it works:

- rustc/cargo (glibc builds) run under **proot**, where `/lib` maps to the glibc libraries (the `libc.so` fallback there is a valid ELF)
- host artifacts (build.rs scripts, proc-macros) compile for the glibc host and also execute inside proot
- target crates build with `--target aarch64-linux-android` and link via Termux `clang` (bionic) — the final ELF is native Android
- PATH order inside proot matters: `~/proot-glibc/bin` (bfd `ld` for collect2) first, then glibc-bin, then Termux — otherwise gcc's collect2 picks up Termux's lld and fails on `--fix-cortex-a53-*` flags

### 3. omp sources

```bash
git clone -b omp2-termux-android-arm64 https://github.com/anatoli-tsinovoy/oh-my-pi omp2-src
cd omp2-src
# then apply the stability patches (see Patches section — or clone the patched fork directly)
```

### 4. Python for crates/py

omp embeds CPython through PyO3. On Termux, the system Python 3.14 is used:

```bash
OMP_PY_TARGET=aarch64-linux-android scripts/fetch-python.sh
# generates vendor/python-android/pyo3-config.txt
```

### 5. Build

```bash
export CARGO_BUILD_JOBS=1     # 8 GB RAM: parallel codegen units get OOM-killed
OMP_PY_TARGET=aarch64-linux-android \
PYO3_CONFIG_FILE=$HOME/omp2-src/vendor/python-android/pyo3-config.txt \
~/nightly/bin/n-cargo build -p omp-app --bin omp \
  --target aarch64-linux-android --no-default-features --features android --locked
```

Result: `target/aarch64-linux-android/debug/omp` (~1.1 GB debug binary). Optionally:

```bash
strip target/aarch64-linux-android/debug/omp   # → ~760 MB
cp target/aarch64-linux-android/debug/omp ~/.local/bin/omp
```

Build time: ~40–50 minutes (8 cores, thermal throttling, `CARGO_BUILD_JOBS=1`).

## Post-install setup

omp encrypts provider credentials with AES; non-interactive sessions need the local key file:

```bash
echo 'export OMP_LLM_KEY_SOURCE=local-file' >> ~/.bashrc
```

Provider example (an OpenAI-compatible endpoint; note that some strict-JSON providers like Groq reject omp's generated tool schemas):

```bash
cat > ~/.local/share/omp/models.toml <<'TOML'
[providers.bai]
baseUrl = "https://api.b.ai/v1"
auth = "bearer"
disableStrictTools = true

[providers.bai.models."glm-5.3-flash"]
name = "GLM 5.3 Flash (b.ai free)"
api = "openai-completions"
contextWindow = 131072
maxTokens = 32768
TOML

echo "YOUR_API_KEY" | omp auth login bai
```

Running:

```bash
omp print --model glm-5.3-flash "hello"         # one-shot
omp chat --model glm-5.3-flash                  # interactive chat with tools
```

## Patches

The `omp2-termux-android-arm64-fixes` branch on top of f15374e:

1. Removed all `#![feature(...)]` from crates/* (type_alias_impl_trait, impl_trait_in_assoc_type, duration_constructors, extend_one, min_specialization, core_intrinsics, const_eval_select, maybe_uninit_uninit_array_transpose)
2. `type Future = impl Future<…>` (33 files) → `Pin<Box<dyn Future<…> + Send>>`; `fn call` bodies wrapped in `Box::pin(async move { … })` with the **synchronous prefix hoisted out** of the async block (otherwise `&mut self` borrows don't survive `'static`)
3. Opaque iterators → concrete types: `MapIndices` (sparse_map/sparse_set), `FlattenSlices` (append_vec), `ObjectIterInner/ObjectIterMutInner` (slopjson)
4. `sf!("literal")` in const contexts → `Str::new_static(...)`
5. `Duration::from_days(n)` → `from_secs(n*86400)`, `extend_one` → `extend(once(..))`, `uninit().transpose()` → `[MaybeUninit; N]` arrays

The build was verified with rustc 1.99.0-nightly (1a98b1e13 2026-08-07) and cargo 1.99.0-nightly.

## Known limitations

- Debug+stripped binary is ~760 MB (no LTO/release build — release ran out of RAM/time on-device; retry with `--release` and `CARGO_PROFILE_RELEASE_DEBUG=0` if you have more headroom)
- The e2e crate doesn't build (llama-cpp-sys requires NDK) — it's not part of the `omp-app` dependency graph
- Groq-style strict-JSON providers reject schemars-generated tool schemas — use providers without strict JSON Schema requirements (e.g. b.ai) or set `disableStrictTools`
- The proot wrapper routes *all* glibc host binaries through proot: slower than native, but fully transparent to cargo

## License

omp is MIT (© Stencil Labs, Inc.). The recipes in this repository are MIT.
