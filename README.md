# hdl-probe

`hdl_probe` is an HDL path probe library centered on a single core package, `hdl_probe_pkg`, with Dsim and additive XEZIM build targets. It supports packed 4-state logic (`0/1/X/Z`) and `real`.
The DPI declarations live in that package file, so the SV side carries as a single package source.

## Build and run

### Dsim (unchanged default simulator)

```bash
make                       # example-all: core, then UVM 2020.3.1
make build-lib
make example-core
make example-uvm
make test-core-dsim
```

`DSIM_HOME` and `DSIM_LICENSE` retain their original defaults and can be overridden on the make command line. Dsim still uses `+acc+rwcbf`. Its library retains the original artifact path **`build/libhdl_probe_dpi.so`** for existing consumers; per-top run directories use `build/dsim/`. XEZIM's library remains separate at `build/xezim/libhdl_probe_dpi.so`.

### XEZIM (opt-in; validated configuration)

Core regressions and both examples passed on worker-01 with official **XEZIM 0.11.3**, source `9fadb2eb4996d5b18100455e82e27f0de573fa4f` and pinned xezim-core `0cf68756f152f6dc1d2328d720e5c5a95bc90612` (Linux x86_64). The separate UVM smoke passed with official `accellera-official/uvm-core` tag **2020.3.1**, commit `78c06547a2a0a29b3dc9dcafae62b75b2ff61544`, without `UVM_NO_DPI`.

See the [validation record](evidence/xezim-0.11.3/README.md) for raw logs, source/binary hashes, build profile and reproduction commands. The binary banner reports `git unknown` because `.git` was omitted from transfer; source identity comes from recorded provenance, not the version banner alone.

Use an already prepared official XEZIM installation/source checkout. No make recipe downloads XEZIM or UVM, or builds/patches the simulator.

```bash
make build-lib-xezim XEZIM_SOURCE=/absolute/path/to/xezim
make example-core-xezim XEZIM_SOURCE=/absolute/path/to/xezim
make test-core-xezim XEZIM_SOURCE=/absolute/path/to/xezim
```

Configuration (use absolute paths because simulations run in per-top directories):

| Variable | Default / meaning |
| --- | --- |
| `XEZIM_SOURCE` | `$(ROOT)/tools/xezim`; used only to derive default paths |
| `XEZIM` | `$(XEZIM_SOURCE)/target/release/xezim`; explicit executable override |
| `XEZIM_INCLUDE` | `$(XEZIM_SOURCE)/include`; official `svdpi.h`, `vpi_user.h`, `sv_vpi_user.h` |
| `XEZIM_UVM_SRC` | `$(UVM_SRC)`; explicit directory containing `uvm_pkg.sv` and `uvm_macros.svh` |
| `XEZIM_CC` | `$(CC)` (default `gcc`); C compiler executable, also passed to XEZIM for export glue |
| `XEZIM_CFLAGS` | `-std=c11 -fPIC -g -Wall -Wextra -Werror` |
| `XEZIM_LDFLAGS` | Additional library link options, empty by default |
| `XEZIM_FLAGS` | `--no-cache --error-exit --max-time 2us` |
| `RUN_TIMEOUT` | Per-simulator wall-clock bound in seconds, default `120` |

Explicit executable/header overrides work without relying on the source-path defaults:

```bash
make test-core-xezim \
  XEZIM=/absolute/path/to/xezim \
  XEZIM_INCLUDE=/absolute/path/to/official/include
```

Run UVM separately with a prepared, version-recorded **official** UVM source tree:

```bash
make example-uvm-xezim \
  XEZIM_SOURCE=/absolute/path/to/xezim \
  XEZIM_UVM_SRC=/absolute/path/to/official-uvm/src
```

`example-all-xezim` explicitly runs both examples. UVM sources are passed first with their include directory; no `UVM_NO_DPI` or substitute UVM package is used. XEZIM's documented built-in UVM DPI helpers remain enabled. The UVM example is an integration smoke test of the typed probe helpers, not a full UVM phasing test.

XEZIM's library is `build/xezim/libhdl_probe_dpi.so`. Each run writes `build/xezim/<top-or-example>/run.log`; its private `tmp/` contains any temporary export-glue files. Dsim and XEZIM do not share libraries, simulation directories, or logs. Do not run the same target concurrently against the same build directory on a shared worker.

### Callback integration and portability

The callback path remains **VPI `cbValueChange` → C callback → package-scope DPI export `hdl_probe_value_change_notify(int)` → class change counter → `wait` wakeup**. Value caching, callback snapshots, duplicate registrations, removal and public API signatures are unchanged; there is no polling fallback or simulator-specific SV substitute.

For the validated XEZIM revision:

- `src/compiler/simulator/dpi_imports.rs` loads generated DPI-export trampolines **before** user libraries, with global symbol visibility. Load the probe using `--dpi-lib`, not `--vpi-lib` (it has no `vlog_startup_routines`).
- `dpi_export.rs` generates the C entry for the SV export, compiles it at simulation startup using `$CC` (a compiler executable, not a shell command plus flags), then loads it. A C compiler must therefore be available **on the execution worker**, even with a prebuilt XEZIM binary. The probe retains an unresolved `extern void hdl_probe_value_change_notify(int)` for that glue to resolve; do not stub, weaken or replace it.
- `dpi_task.rs` resolves package exports; `vpi_cb.rs` establishes active simulator context while invoking callbacks. Passing core/waiter regressions validate the direct callback chain, including reentrant `p.read()` and callback self-removal. No simulator patches or additional hand-written export glue were needed.

The shared C code includes an experimentally verified baseline fix and portability hardening:

1. Open-array indexing used `svLow + chunk * svIncrement`. DPI `$increment` is `-1` for the package's ascending `int words[32]` arrays, so cross-word reads addressed below the lower bound. Mapping chunks to `svLow + chunk` preserves lowest-index-first ordering for both directions. The unchanged baseline C compiled against XEZIM headers but failed the **same** `probe_values` regression at width 33 with `HDL_PROBE_READ_ERROR` (status 4, process exit 1); the corrected C passed all tested widths/patterns.
2. A VPI vector word was assigned directly to `svLogicVecVal`. Equal layouts do not make distinct C struct types assignment-compatible. Using `s_vpi_vecval` for VPI data avoids that assumption. XEZIM aliases the two types, so this is portability hardening, **not an observed XEZIM compilation failure**. A zero-initialized/null-checked VPI vector also prevents dereferencing a missing result.

## Regression coverage and evidence

**Validated on 2026-10-31, 06:00:36–06:00:56 UTC:** `example-core-xezim`, all three `test-core-xezim` tops below, and separately `example-uvm-xezim` passed with exact `HDL_PROBE_PASS <top>` markers and exit 0. The strict C build (`-Wall -Wextra -Werror`) passed. Worker checks of `tests/run_checked.sh` confirmed exit 0 for a marker, exit 1 without a marker, preservation of exit 7 after a marker, and timeout exit 124; Bash syntax also passed.

The runner requires both a successful process exit and the exact marker line. Each SV regression has a 500 ns `$fatal` watchdog (examples: 100 ns), a 120 s default wall-clock bound and, for XEZIM, an additional maximum-time cap. A time cap or clean exit alone is not a pass.

| Top | Checks |
| --- | --- |
| `probe_values` | Packed widths 1/31/32/33/1024, all-0/1/X/Z, mixed and sparse cross-word patterns, width/kind/path, zero upper bits, typed and instance reads, literal raw 33-bit words/masking with ascending/descending nonzero array bounds, real read, wrong-kind helpers, value copy/clear, missing path, 1025-bit rejection |
| `probe_callbacks` | Two waiters on one change, counter and callback values, logic X/Z, real read/change, reentrant reads, same-value writes, callback removal, duplicate registration/single removal, self-removal, typed waits, last-waiter callback removal/re-enable |
| `probe_lifecycle` | Path cache identity, registration before connect, idempotent destroy, reconnect with retained class callbacks, cleanup with live callback, repeated cleanup, reset caches/keys/scope, new probe after cleanup, post-cleanup callback/wait and no stale delivery |

The expected values come from SV literals/bit-state oracles, not probe reads. Tops run as separate bounded processes; a failure is retained while remaining tops are attempted. To isolate a failure, for example:

```bash
make test-core-xezim CORE_TESTS=probe_callbacks XEZIM_SOURCE=/absolute/path/to/xezim
```

Limits of this validation:

- **Dsim runtime regressions: NOT_RUN** (no prepared worker installation). Dsim remains the default with its existing setup/flags; it is not newly certified by the XEZIM results.
- **Verible/slang lint: NOT_RUN.**
- Results apply to the recorded XEZIM revision/configuration, not every 0.11.3 revision, architecture or use case. The UVM example is typed-helper/reporting smoke, not full phasing coverage.
- Cleanup during an already-blocked waiter is untested; the baseline has no cancellation API. No new cancellation semantics are introduced.
- Resource observations in the evidence are single runs on a shared worker, not performance benchmarks.

## Examples

Detailed read style:

```systemverilog
import hdl_probe_pkg::*;

hdl_probe probe;
hdl_probe_value value;
hdl_probe_status_e status;
logic [HdlProbeMaxW-1:0] bits;
int unsigned n_bits;

probe = hdl_probe::get("top.dut.state");
status = probe.read(value);
if (status == HDL_PROBE_OK && value.get_logic(bits, n_bits)) begin
  // use bits[n_bits-1:0]
end
```

Typed helper style:

```systemverilog
import uvm_pkg::*;
import hdl_probe_pkg::*;
`include "uvm_macros.svh"

logic [7:0] bits;
real temp;

if (!hdl_probe::read_logic("top.dut.state", bits)) begin
  `uvm_fatal("READ", "hdl_probe::read_logic failed")
end

if (!hdl_probe::read_real("top.dut.temp", temp)) begin
  `uvm_fatal("READ", "hdl_probe::read_real failed")
end

hdl_probe::wait_logic_change("top.dut.state", bits);
hdl_probe::wait_real_change("top.dut.temp", temp);
```

The typed helper APIs can write into a narrower packed variable when the caller already knows the signal width. For example, an 8-bit signal can be read into `logic [7:0] bits`.

## Notes

- Dsim remains the default; XEZIM targets are explicit and validated within the configuration and coverage above.
- DSim needs `+acc+rwcbf` for the VPI path lookup and value-change callback flow used here.
- `connect()` can return `HDL_PROBE_TOO_WIDE` when a packed logic object exceeds `HdlProbeMaxW`.
- When the caller needs precise failure reason or actual packed width, prefer `hdl_probe::get(path)` plus instance `read()` / `wait_for_change()` over the `bit`-returning typed helpers.
- `hdl_probe::cleanup()` is a full reset: it destroys live probes, clears the path / key caches, resets key allocation, and drops the captured callback scope.
