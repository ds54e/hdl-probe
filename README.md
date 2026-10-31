# hdl-probe

Read and watch HDL signals by path in [Xezim](https://github.com/aionhw/xezim). Supports packed 4-state logic (up to 1024 bits) and `real`.

## Setup

Run from the repository root with Xezim on `PATH`.

```bash
make build-lib XEZIM_SOURCE=/abs/path/to/xezim
CC=cc xezim --dpi-lib build/xezim/libhdl_probe_dpi.so -s top sv/hdl_probe_pkg.sv your_design.sv
```

- `make build-lib` builds the DPI library into `build/xezim/`.
- `CC` must name a C compiler: xezim uses it to build glue code for the package's DPI export.

## Usage

All examples use this design. The usage snippets below are independent fragments for an `initial` block in `top`, with `import hdl_probe_pkg::*;` in the module. Wait examples assume later stimulus from another process; run the intentional `$fatal` example separately.

```systemverilog
module top;
  dut dut();
endmodule

module dut;
  logic [7:0] state = 8'b1100_xz01;
  real        temp  = 1.25;
endmodule
```

There are two ways to use the package:

- **Typed helpers** (`hdl_probe::read_logic` etc.): one call per access. Use them when you know the path is right.
- **Probe objects**: `get()` returns a probe; `read()` returns a status and `wait_for_change()` sets `st`.

### Typed helpers

```systemverilog
logic [7:0]  state;
logic [15:0] wide;
real         temp;
bit          ok;

// Read
ok = hdl_probe::read_logic("top.dut.state", state);  // -> ok = 1, state = 8'b1100_xz01 (X/Z kept)
ok = hdl_probe::read_logic("top.dut.state", wide);   // -> ok = 1, wide = 16'b0000_0000_1100_xz01
ok = hdl_probe::read_real ("top.dut.temp",  temp);   // -> ok = 1, temp = 1.25

// Read failures return 0 and clear the output
ok = hdl_probe::read_logic("top.dut.typo",  state);  // -> ok = 0, state = 0 (no such path)
ok = hdl_probe::read_real ("top.dut.state", temp);   // -> ok = 0, temp = 0  (not a real)

// Wait: blocks until the signal changes, then returns the new value
hdl_probe::wait_logic_change("top.dut.state", state);  // design does state = 8'h42 -> state = 8'h42
hdl_probe::wait_real_change ("top.dut.temp",  temp);   // design does temp = 2.5    -> temp = 2.5

// Wait failures stop the simulation
hdl_probe::wait_logic_change("top.dut.typo", state);   // -> $fatal
```

### Probe objects

```systemverilog
hdl_probe          p;
hdl_probe_value    v;
hdl_probe_status_e st;

// Read
p  = hdl_probe::get("top.dut.state");
st = p.read(v);  // -> st = HDL_PROBE_OK, v.kind = HDL_PROBE_KIND_LOGIC4,
                 //    v.n_bits = 8, v.logic4 = 8'b1100_xz01 (upper bits 0)

p  = hdl_probe::get("top.dut.temp");
st = p.read(v);  // -> st = HDL_PROBE_OK, v.kind = HDL_PROBE_KIND_REAL, v.r = 1.25

// Failures return a status (no $fatal)
p  = hdl_probe::get("top.dut.typo");
st = p.read(v);  // -> st = HDL_PROBE_NOT_FOUND
                 //    (others: HDL_PROBE_UNSUPPORTED_KIND, HDL_PROBE_TOO_WIDE for > 1024 bits)

// Wait
p = hdl_probe::get("top.dut.state");
p.wait_for_change(v, st);  // design does state = 8'h42 -> st = HDL_PROBE_OK, v.logic4 = 8'h42
```
