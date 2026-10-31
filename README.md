# hdl-probe

`hdl_probe_pkg` probes Xezim HDL paths as packed 4-state logic (`0/1/X/Z`) or `real`. API: `sv/hdl_probe_pkg.sv`.

## Examples

The instance API is primary for handling failures: `connect()` and `read(value)` return `hdl_probe_status_e`, while `wait_for_change(value, status)` reports status by reference.

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

Typed helpers are conveniences for known valid paths: reads return a success bit; waits call `$fatal` on failure or kind mismatch.

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

Also available: `destroy()`, `is_valid()`, `get_path()`, `get_kind()`, `get_size()`, `get_change_count()`, and `add_callback(cb)` / `remove_callback(cb)`; subclass `hdl_probe_cb` with `do_on_change(hdl_probe p, hdl_probe_value v)`.

`hdl_probe_value`: public `clear()`, `copy_from(rhs)`, `get_logic(bits, width)` and `get_real(value)` utilities (getters return a success bit).

## Build and run

Supply prepared official Xezim, its headers and a C compiler; make fetches nothing.

```bash
make                       # test-core (default)
make build-lib
make example-core
make test-core
make fmt                   # requires Verible
make lint                  # requires Verible + slang
make clean
```

`XEZIM_SOURCE` defaults to `tools/xezim` (`target/release/xezim`, headers in `include`). Override with `make XEZIM_SOURCE=/absolute/path/to/xezim` or set `XEZIM` and `XEZIM_INCLUDE` separately; use absolute tool paths.

Outputs/logs: `build/xezim/`. `CC` defaults to `cc` and must name an executable for library and DPI glue builds. `CPPFLAGS`, `CFLAGS`, `LDFLAGS` control library options. `XEZIM_FLAGS` defaults to `--no-cache --error-exit --max-time 2us`; `RUN_TIMEOUT` defaults to 120 seconds per run. Runs require exit 0 and an exact PASS marker.

## Notes

- UVM code can import `hdl_probe_pkg::*` normally because the library has no UVM dependency.
- Typed logic outputs may be narrower when the signal width is known; use the instance API for width or precise failure status.
- Typed wait helpers call `$fatal` on failure; typed read helpers return a success bit.
- `connect()` returns `HDL_PROBE_TOO_WIDE` for packed widths above `HdlProbeMaxW` (1024).
- Changes use VPI callbacks, not polling; make loads the library with `--dpi-lib`.
- `hdl_probe::cleanup()` destroys live probes and resets path/key caches and key allocation.
- Pending waits survive `destroy()` / `cleanup()` until the same probe object reconnects and its value changes.
