# hdl-probe

`hdl_probe` is an Xezim HDL path probe library centered on `hdl_probe_pkg`. It supports packed 4-state logic (`0/1/X/Z`) and `real`. The public SV API and DPI declarations live in `sv/hdl_probe_pkg.sv`.

## Build and run

Use a prepared official Xezim executable, its headers and a C compiler. Nothing is downloaded or installed by make.

```bash
make                       # core regressions
make build-lib
make example-core
make test-core
make clean
```

`XEZIM_SOURCE` defaults to `tools/xezim` in this checkout, with executable `target/release/xezim` and headers in `include`. Override it with `make XEZIM_SOURCE=/absolute/path/to/xezim`, or set `XEZIM` and `XEZIM_INCLUDE` independently. Use absolute tool paths because simulations run in per-top directories.

The library and run logs are under `build/xezim/`. `CC` defaults to `cc`; use `CPPFLAGS`, `CFLAGS` and `LDFLAGS` for library build options. `CC` must name a compiler executable: Xezim also uses it to generate DPI-export glue, even with a prebuilt simulator. `XEZIM_FLAGS` defaults to `--no-cache --error-exit --max-time 2us`; `RUN_TIMEOUT` defaults to 120 seconds per run. Examples/regressions require an exact PASS marker and exit 0.

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
import hdl_probe_pkg::*;

logic [7:0] bits;
real temp;

if (!hdl_probe::read_logic("top.dut.state", bits))
  $fatal(1, "logic read failed");
if (!hdl_probe::read_real("top.dut.temp", temp))
  $fatal(1, "real read failed");

hdl_probe::wait_logic_change("top.dut.state", bits);
hdl_probe::wait_real_change("top.dut.temp", temp);
```

## Notes

- UVM code can import `hdl_probe_pkg::*` normally because the library has no UVM dependency.
- Typed logic helpers can write into a narrower packed variable when the caller knows the signal width. For actual width or precise failure status, prefer instance `read()` / `wait_for_change()`.
- Typed wait helpers call `$fatal` on failure; typed read helpers return a success bit.
- `connect()` returns `HDL_PROBE_TOO_WIDE` for packed widths above `HdlProbeMaxW` (1024).
- Changes use VPI callbacks through the package DPI export, not polling. The build loads the library with `--dpi-lib`.
- `hdl_probe::cleanup()` destroys live probes and resets path/key caches and key allocation.
- Pending waits survive `destroy()` / `cleanup()` until the same probe object reconnects and its value changes.
