# XEZIM 0.11.3 validation record

**Result:** the core example, three core regression tops and separate official-UVM smoke passed on worker-01, 2026-10-31 06:00:36–06:00:56 UTC. Each reached its exact `HDL_PROBE_PASS <top>` marker; checked make targets exited 0. No simulator patches, API changes, polling fallback or replacement SV package were needed.

## Provenance

| Component | Recorded identity |
| --- | --- |
| hdl-probe baseline | `7eca94110d9f7b71f30f0ee1336085b5c2e0568c` |
| Tested snapshot | `source-001`, 13 files; original per-file SHA256 values in [source-001.json](source-001.json) |
| Snapshot archive SHA256 | `a0c736a1999d4b61a0174598d0448344c8143d72597daf0bce50b81e06aa842a` |
| Official XEZIM source | [aionhw/xezim](https://github.com/aionhw/xezim), `9fadb2eb4996d5b18100455e82e27f0de573fa4f` |
| Pinned xezim-core / sv-parser | `0cf68756f152f6dc1d2328d720e5c5a95bc90612`; also recorded in [xezim-Cargo.lock](xezim-Cargo.lock) |
| Executable SHA256 | `fb3978c53423d130e9aee0ece76f8fe9aef802b950f42e43f4e5257845f8116c` |
| Official UVM | [accellera-official/uvm-core](https://github.com/accellera-official/uvm-core), tag `2020.3.1`, commit `78c06547a2a0a29b3dc9dcafae62b75b2ff61544` |
| Worker/toolchain | Shared worker-01; AlmaLinux 9.8, x86_64; Rust/Cargo 1.92.0, GCC 11.5.0 |

The binary's [`-V` output](xezim-version.log) reports `xezim version 0.11.3`, `git unknown (unknown)`, `tag unknown`: `.git` was deliberately excluded from source transfer. The exact source revision is recorded build provenance, **not proven by the banner alone**. Actual `--help` output confirmed the used options (retained with the full operational evidence).

The tested build/runtime files were `Makefile`, `c/hdl_probe.c`, unchanged `sv/hdl_probe_pkg.sv`, both `examples/example_{core,uvm}.sv`, the three `tests/probe_{values,callbacks,lifecycle}.sv` files and `tests/run_checked.sh`. The other snapshot files were `README.md`, `.gitignore`, `.rules.verible_lint` and `LICENSE`.

**Final Makefile verification:** `DSIM_LIB` retains the original `build/libhdl_probe_dpi.so`, while XEZIM uses `build/xezim/libhdl_probe_dpi.so`. After correcting the initial Dsim artifact-path change, snapshot `source-002` passed a fresh strict C build and core example at **06:07:37 UTC** (exit 0, 0.190 s, 41640 KiB max RSS). A Dsim build dry-run confirmed the legacy output path; this is not a Dsim runtime test. All C/SV/example/test/runner hashes match the fully tested `source-001`; only Makefile and documentation changed. See [final-verification.json](final-verification.json), [source-002.json](source-002.json), [example-core-002.log](example-core-002.log) and [dsim-build-dry-run-002.log](dsim-build-dry-run-002.log). Snapshot README hashes identify historical documentation, not this updated record.

## Observed results

| Checked target | Result / markers | Wall seconds | Reported max RSS (KiB) |
| --- | --- | ---: | ---: |
| `example-core-xezim` | PASS, `example_core`, exit 0 | 0.142 | 41768 |
| `test-core-xezim` | PASS, `probe_values`, `probe_callbacks`, `probe_lifecycle`, aggregate exit 0 | 0.823 | 42012 |
| `example-uvm-xezim` | PASS, `example_uvm`, exit 0 | 0.695 | 196204 |

The core example validates logic and real callback waits. Core regression coverage includes packed widths 1/31/32/33/1024 with 0/1/X/Z and upper-bit zeroing, sparse/mixed word patterns, literal raw words, real reads/changes, wrong-kind/missing-path errors, width 1025 rejection, reentrant reads, two waiters, duplicate/single/self callback removal, cleanup and reconnect. See the repository [coverage table](../../README.md#regression-coverage-and-evidence).

The UVM log identifies `Accellera:1800.2:UVM:2020.3.1`; `UVM_NO_DPI` was not defined. This checks typed helpers and reporting, **not a complete UVM phasing suite**.

- Strict library build with `-std=c11 -fPIC -g -Wall -Wextra -Werror`: PASS, exit 0.
- Bash syntax: PASS. Runner checks: exact marker → 0; no marker → 1; marker then process exit 7 → 7; timeout → 124. See [runner-checks.json](runner-checks.json).
- Negative control: unchanged baseline C **compiled successfully** against official XEZIM headers, then the identical `probe_values` test exited 1 at width 33: `** Fatal: probe_values.w33 metadata/read failed status=4`. The corrected library passed the same regression. This experimentally supports the open-array indexing fix. The VPI/DPI struct-type adjustment is portability hardening; XEZIM aliases those types, and no compilation failure was observed there.

These are single-run resource observations, **not controlled performance benchmarks**. Tests were sequential; no other active simulator/compiler was observed before launches, but worker-01 was shared, not reserved. The simulator build reported 12m21s; sampling observed about 1.4 GiB RSS and up to 1661 MiB **total host swap used**, not a precise build peak. Memory recovered after the build; the tests were substantially lighter.

## Reproduction on an authorized execution worker

Have Dot prepare the exact official source/UVM refs above and Rust/Cargo 1.92.0 plus GCC 11.5.0. Use the recorded `xezim-Cargo.lock` as `tools/xezim/Cargo.lock`. No download, installation or simulator-source patching is part of the hdl-probe make recipes.

Simulator build, with the recorded profile overrides:

```bash
root=/home/dot-worker/hdl-probe-20261031
export CARGO_HOME="$root/tools/cargo" RUSTUP_HOME="$root/tools/rustup"
export PATH="$CARGO_HOME/bin:$PATH"
cd "$root/tools/xezim"
CARGO_BUILD_JOBS=1 \
CARGO_PROFILE_RELEASE_LTO=false \
CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
CARGO_PROFILE_RELEASE_DEBUG=0 \
nice -n 10 cargo build --release --bin xezim --locked
```

The actual recorded build used `cargo build --release --bin xezim` with these environment overrides and niceness. `--locked` is added above to enforce the supplied dependency resolution during reproduction; it was not in the original command. The recorded binary hash identifies that built artifact, not a promise of byte-identical output from another build environment.

The following reruns the checked targets against the original frozen source directory. Source paths, used options and target commands are also recorded in [manifest.json](manifest.json) and the make logs. For another checkout, change only the checkout/tool paths. Run sequentially, not concurrently in the same build directory:

```bash
root=/home/dot-worker/hdl-probe-20261031
cd "$root/source-001"
make -j1 build-lib-xezim XEZIM_SOURCE="$root/tools/xezim"
make -j1 example-core-xezim XEZIM_SOURCE="$root/tools/xezim" RUN_TIMEOUT=120
make -j1 test-core-xezim XEZIM_SOURCE="$root/tools/xezim" RUN_TIMEOUT=120
make -j1 example-uvm-xezim XEZIM_SOURCE="$root/tools/xezim" \
  XEZIM_UVM_SRC="$root/tools/uvm-core/src" RUN_TIMEOUT=120
```

Defaults supply `--no-cache --error-exit --max-time 2us`, `--dpi-lib`, the strict C flags and a 120 s per-process timeout. Exact marker checks, watchdogs and nonzero-status propagation remain required. Per-top logs are `source-001/build/xezim/*/run.log`. XEZIM generates/compiles its DPI-export trampoline at startup, so a C compiler is still required with a prebuilt simulator.

## Evidence locations

This directory contains the selected raw records:

| Files | Contents |
| --- | --- |
| `manifest.json`, `source-001.json` | Provenance, original snapshot hashes, commands, target exit statuses and resource observations |
| `build-lib-001.log` | Strict C build command/output |
| `example-core-001.log`, `core-regression-001.log`, `example-uvm-001.log` | Complete checked make output |
| `example-core.log`, `probe_values.log`, `probe_callbacks.log`, `probe_lifecycle.log`, `example-uvm.log` | Raw per-top simulator output |
| `runner-checks.json` | Expected and observed runner exit statuses |
| `baseline-build.log`, `baseline-values-run.log`, `baseline-values-exit.txt` | Baseline negative control; empty build log means no compiler diagnostics, not failure |
| `xezim-build-start.txt`, `xezim-build-exit.txt`, `xezim-version.log`, `xezim-Cargo.lock` | Build timestamps/status, version output and dependency resolution |

Full operational evidence is retained **outside the repository**, at `../worker-evidence/`, `../worker-evidence-001.tar.gz` and `../worker-evidence-002.tar.gz` (paths relative to the repository root). It includes build/help logs, process/resource snapshots, runner wrapper logs and original per-top logs. Archive 001 SHA256 is `947fdc45d25dd66e6ee9361d467ffee3223b8e18da89495f117a04b7f7a893c5`; archive 002 adds final Makefile, tool-version and runner-check records, SHA256 `893fbdba790c3de6eb5fb0bb924950dd2e511df11370aa11a703e23023131aa5`.

## Limitations / readiness

The Dsim artifact-path finding is corrected and the final dispatch/hash verification is complete. No outstanding material correctness blocker was identified in the scoped source/evidence review. This is validated support for the recorded configuration and tested behaviors, **not exhaustive compatibility**.

- Dsim runtime regression: **NOT_RUN**, no prepared installation on worker-01; its default setup/flags remain preserved.
- Verible/slang lint: **NOT_RUN**.
- Other XEZIM revisions, architectures and build profiles: unvalidated.
- Cleanup of an already-blocked waiter: untested; baseline has no cancellation API.
- UVM phasing and broader UVM behavior: not established by this smoke test.
