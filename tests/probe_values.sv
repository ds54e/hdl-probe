module probe_values;
  timeunit 1ns; timeprecision 1ps;
  import hdl_probe_pkg::*;

  logic w1;
  logic [30:0] w31;
  logic [31:0] w32;
  logic [32:0] w33;
  logic [1023:0] w1024;
  logic [1024:0] w1025;
  real analog_value;

  initial begin : watchdog
    #500ns;
    $fatal(1, "probe_values timeout");
  end

  // The oracle uses SV bit states, not VPI aval/bval packing or probe reads.
  function automatic logic expected_bit(int mode, int unsigned index);
    case (mode)
      0: return 1'b0;
      1: return 1'b1;
      2: return 1'bx;
      3: return 1'bz;
      4: begin
        case (index % 4)
          0: return 1'b0;
          1: return 1'b1;
          2: return 1'bx;
          3: return 1'bz;
          default: return 1'bx;
        endcase
      end
      5: begin
        case (index)
          0, 32, 511: return 1'b1;
          30, 63, 512: return 1'bx;
          31, 64, 1023: return 1'bz;
          default: return 1'b0;
        endcase
      end
      default: $fatal(1, "bad oracle mode %0d", mode);
    endcase
    return 1'bx;
  endfunction

  task automatic drive(int mode);
    case (mode)
      0: w1024 = '0;
      1: w1024 = '1;
      2: w1024 = 'x;
      3: w1024 = 'z;
      4: w1024 = {256{4'bzx10}};
      5: begin
        w1024 = '0;
        w1024[0] = 1'b1;
        w1024[30] = 1'bx;
        w1024[31] = 1'bz;
        w1024[32] = 1'b1;
        w1024[63] = 1'bx;
        w1024[64] = 1'bz;
        w1024[511] = 1'b1;
        w1024[512] = 1'bx;
        w1024[1023] = 1'bz;
      end
      default: $fatal(1, "bad drive mode %0d", mode);
    endcase
    w1  = w1024[0];
    w31 = w1024[30:0];
    w32 = w1024[31:0];
    w33 = w1024[32:0];
  endtask

  task automatic check_packed(string path, int unsigned width, int mode);
    hdl_probe p;
    hdl_probe_value v;
    hdl_probe_status_e st;
    logic [HdlProbeMaxW-1:0] bits;
    logic [HdlProbeMaxW-1:0] typed_bits;
    int unsigned actual_width;
    real wrong_real;

    p = hdl_probe::get(path);
    v = new();
    v.logic4 = 'x;  // Reads must clear previous data, including upper bits.
    st = p.read(v);
    if (st != HDL_PROBE_OK || !p.is_valid() || p.get_kind() != HDL_PROBE_KIND_LOGIC4 ||
        p.get_size() != width || p.get_path() != path) begin
      $fatal(1, "%s metadata/read failed status=%0d", path, st);
    end
    if (!v.get_logic(bits, actual_width) || actual_width != width) begin
      $fatal(1, "%s value width failed", path);
    end
    typed_bits = 'x;
    if (!hdl_probe::read_logic(path, typed_bits)) begin
      $fatal(1, "%s typed read failed", path);
    end
    for (int unsigned i = 0; i < HdlProbeMaxW; i++) begin
      if (i < width) begin
        if (bits[i] !== expected_bit(mode, i) || typed_bits[i] !== expected_bit(mode, i)) begin
          $fatal(1, "%s mode=%0d bit=%0d expected=0b%0b actual=0b%0b typed=0b%0b", path, mode, i,
                 expected_bit(mode, i), bits[i], typed_bits[i]);
        end
      end else if (bits[i] !== 1'b0 || typed_bits[i] !== 1'b0) begin
        $fatal(1, "%s upper bit %0d not zero", path, i);
      end
    end
    wrong_real = 123.0;
    if (v.get_real(wrong_real) || wrong_real != 0.0) begin
      $fatal(1, "get_real on logic must fail and zero output");
    end
  endtask

  // Contract test of the C DPI layer: read() clears its value first,
  // so only a direct call can show missing upper-word zeroing.
  task automatic check_raw_zero_fill(int mode);
    chandle h;
    int c_status;
    int c_kind;
    int c_size;
    logic [HdlProbeMaxW-1:0] raw;

    h = hdl_probe_dpi_create("probe_values.w33", -1, c_status, c_kind, c_size);
    if (h == null || c_status != HDL_PROBE_OK) begin
      $fatal(1, "raw create failed");
    end
    if (c_kind != HDL_PROBE_KIND_LOGIC4 || c_size != 33) begin
      $fatal(1, "raw create metadata mismatch: kind=%0d size=%0d", c_kind, c_size);
    end
    raw = 'x;
    if (!hdl_probe_dpi_read_logic(h, raw)) begin
      $fatal(1, "raw read failed mode=%0d", mode);
    end
    for (int unsigned i = 0; i < HdlProbeMaxW; i++) begin
      if (i < 33 ? raw[i] !== expected_bit(mode, i) : raw[i] !== 1'b0) begin
        $fatal(1, "raw mode=%0d bit=%0d actual=0b%0b", mode, i, raw[i]);
      end
    end
    if (!hdl_probe_dpi_destroy(h)) begin
      $fatal(1, "raw destroy failed");
    end
  endtask

  initial begin : test
    hdl_probe p;
    hdl_probe_value v;
    hdl_probe_value copied;
    hdl_probe_status_e st;
    logic [HdlProbeMaxW-1:0] bits;
    int unsigned width;
    real r;

    w1025 = '0;
    analog_value = -3.25;
    drive(0);
    #1ns;
    for (int mode = 0; mode < 6; mode++) begin
      drive(mode);
      #1ns;
      check_packed("probe_values.w1", 1, mode);
      check_packed("probe_values.w31", 31, mode);
      check_packed("probe_values.w32", 32, mode);
      check_packed("probe_values.w33", 33, mode);
      check_packed("probe_values.w1024", 1024, mode);
      check_raw_zero_fill(mode);
    end

    p  = hdl_probe::get("probe_values.analog_value");
    st = p.read(v);
    if (st != HDL_PROBE_OK || p.get_kind() != HDL_PROBE_KIND_REAL || p.get_size() != 64) begin
      $fatal(1, "real metadata/read failed status=%0d", st);
    end
    if (!v.get_real(
            r
        ) || r != -3.25 || !hdl_probe::read_real(
            "probe_values.analog_value", r
        ) || r != -3.25) begin
      $fatal(1, "real read mismatch");
    end
    bits  = 'x;
    width = 99;
    if (v.get_logic(bits, width) || bits !== '0 || width != 0) begin
      $fatal(1, "get_logic on real must fail and zero outputs");
    end
    if (hdl_probe::read_logic("probe_values.analog_value", bits) || bits !== '0) begin
      $fatal(1, "typed logic on real must fail and zero output");
    end
    if (hdl_probe::read_real("probe_values.w33", r) || r != 0.0) begin
      $fatal(1, "typed real on logic must fail and zero output");
    end

    copied = new();
    copied.copy_from(v);
    v.clear();
    if (!copied.get_real(
            r
        ) || r != -3.25 || v.kind != HDL_PROBE_KIND_UNKNOWN || v.n_bits != 0 || v.logic4 !== '0 ||
            v.r != 0.0) begin
      $fatal(1, "value copy/clear mismatch");
    end
    copied.copy_from(null);
    if (copied.kind != HDL_PROBE_KIND_UNKNOWN || copied.n_bits != 0 ||
        copied.logic4 !== '0 || copied.r != 0.0) begin
      $fatal(1, "copy_from(null) mismatch");
    end

    p  = hdl_probe::get("probe_values.missing");
    st = p.connect();
    if (st != HDL_PROBE_NOT_FOUND || p.is_valid()) begin
      $fatal(1, "missing path status=%0d", st);
    end
    st = p.read(v);
    if (st != HDL_PROBE_NOT_FOUND) begin
      $fatal(1, "missing read status=%0d", st);
    end
    if (hdl_probe::read_logic("probe_values.missing", bits) || bits !== '0) begin
      $fatal(1, "missing typed read mismatch");
    end
    p  = hdl_probe::get("probe_values.w1025");
    st = p.connect();
    if (st != HDL_PROBE_TOO_WIDE || p.is_valid()) begin
      $fatal(1, "1025-bit connect status=%0d", st);
    end
    st = p.read(v);
    if (st != HDL_PROBE_TOO_WIDE || p.is_valid()) begin
      $fatal(1, "1025-bit read status=%0d", st);
    end

    hdl_probe::cleanup();
    $display("HDL_PROBE_PASS probe_values");
    $finish;
  end
endmodule
