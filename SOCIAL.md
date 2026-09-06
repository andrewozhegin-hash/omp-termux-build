# Посты для шаринга (копируй и вставляй)

## Reddit r/termux (тоже подойдёт r/rust, r/LocalLLaMA)

**Title:** I built a full AI coding agent (oh-my-pi) natively on my Android phone — no root, no NDK. Prebuilt binary + full recipe inside.

**Body:**

Saw "This Free Terminal Agent Made Me Delete Claude Code" on YouTube and wanted it running in Termux. The official binary segfaults on Android, so I:

1. Assembled a nightly Rust toolchain from rust.org tarballs (glibc host running under proot!) — Termux only ships stable Rust
2. Patched 36 source files to remove all nightly feature gates
3. Built the whole thing ON-DEVICE (Samsung, 8GB RAM, ~50 min, CARGO_BUILD_JOBS=1)
4. Hooked up an OpenAI-compatible provider (b.ai) — Groq's strict JSON schema validation rejects omp's tool schemas

It works. Full agent chat with read/edit/bash tools, straight from my pocket. 📱🦀

- Prebuilt binary (108 MB) + one-command install: https://github.com/andrewozhegin-hash/omp-termux-build
- Patched source: https://github.com/andrewozhegin-hash/omp-termux-src

Happy to answer questions about the proot toolchain trick — that part is reusable for ANY nightly-Rust project on Termux.

## Hacker News

**Title:** Show HN: Building a Rust AI coding agent natively on Android/Termux (proot nightly toolchain)

**Body:** Prebuilt oh-my-pi (omp) binary for Termux aarch64, plus the complete recipe: glibc nightly toolchain under proot, host/target linker split (glibc gcc for build scripts, Termux clang for the bionic target), 36 source patches removing feature gates. The proot toolchain approach generalizes to any nightly-Rust project on Termux. ~50 min build on a phone, no NDK/cross-compilation/root.

## Twitter/X

Built a full AI coding agent NATIVELY on my Android phone 📱🦀

Official binary segfaults → assembled a nightly Rust toolchain from tarballs, ran it under proot, patched 36 files, compiled on-device in 50 min.

Now Claude Code-class agent lives in my pocket. Prebuilt binary + recipe: 👇
https://github.com/andrewozhegin-hash/omp-termux-build
