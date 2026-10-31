module probe_callbacks;
  timeunit 1ns;
  timeprecision 1ps;
  import hdl_probe_pkg::*;

  logic [32:0] observed;
  real analog_value;

  class checking_cb extends hdl_probe_cb;
    int calls = 0;
    hdl_probe expected_probe;
    hdl_probe_kind_e expected_kind;
    logic [HdlProbeMaxW-1:0] expected_bits = '0;
    real expected_real;
    bit remove_self = 0;

    virtual function void do_on_change(hdl_probe p, hdl_probe_value v);
      hdl_probe_value nested;
      hdl_probe_status_e st;
      calls++;
      if (p != expected_probe || v == null || v.kind != expected_kind)
        $fatal(1, "callback identity/kind mismatch");
      // This reenters DPI/VPI while the original VPI callback is on the stack.
      st = p.read(nested);
      if (st != HDL_PROBE_OK || nested == null) $fatal(1, "callback nested read failed");
      if (expected_kind == HDL_PROBE_KIND_LOGIC4) begin
        if (v.n_bits != 33 || v.logic4 !== expected_bits || nested.logic4 !== expected_bits)
          $fatal(1, "callback logic snapshot/nested read mismatch");
      end else begin
        if (v.n_bits != 64 || v.r != expected_real || nested.r != expected_real)
          $fatal(1, "callback real snapshot/nested read mismatch");
      end
      if (remove_self) p.remove_callback(this);
    endfunction
  endclass

  task automatic logic_waiter(hdl_probe p, logic [32:0] expected);
    hdl_probe_value v;
    hdl_probe_status_e st;
    logic [HdlProbeMaxW-1:0] full_expected;
    full_expected = '0;
    full_expected[32:0] = expected;
    p.wait_for_change(v, st);
    if (st != HDL_PROBE_OK || v == null) $fatal(1, "logic waiter status=%0d", st);
    if (v.kind != HDL_PROBE_KIND_LOGIC4 || v.n_bits != 33 || v.logic4 !== full_expected)
      $fatal(1, "logic waiter value mismatch");
  endtask

  initial begin : watchdog
    #500ns;
    $fatal(1, "probe_callbacks timeout: VPI -> C -> package DPI export -> class wait did not complete");
  end

  initial begin : test
    hdl_probe p;
    hdl_probe rp;
    hdl_probe_value rv;
    hdl_probe_status_e st;
    checking_cb cb;
    checking_cb rcb;
    checking_cb self_cb;
    int unsigned count_before;
    real typed_real;
    logic [HdlProbeMaxW-1:0] typed_logic;

    observed = '0;
    analog_value = 0.5;
    #1ns;
    p = hdl_probe::get("probe_callbacks.observed");
    st = p.connect();
    if (st != HDL_PROBE_OK || p.get_change_count() != 0) $fatal(1, "logic connect failed");
    rp = hdl_probe::get("probe_callbacks.analog_value");
    st = rp.read(rv);
    if (st != HDL_PROBE_OK || rv == null) $fatal(1, "initial real read failed");
    if (rv.r != 0.5) $fatal(1, "initial real mismatch");

    cb = new();
    cb.expected_probe = p;
    cb.expected_kind = HDL_PROBE_KIND_LOGIC4;
    cb.expected_bits[32:0] = {1'bx, 32'h80000001};
    p.add_callback(cb);
    // Both waiters must wake from the same counter change, not a polling loop.
    fork
      logic_waiter(p, {1'bx, 32'h80000001});
      logic_waiter(p, {1'bx, 32'h80000001});
      begin
        #1ns;
        observed = {1'bx, 32'h80000001};
      end
    join
    #1ns;
    if (cb.calls != 1 || p.get_change_count() != 1) $fatal(1, "multiple waiter/callback count mismatch");
    observed = {1'bx, 32'h80000001};
    #1ns;
    if (cb.calls != 1 || p.get_change_count() != 1) $fatal(1, "same-value write delivered callback");

    rcb = new();
    rcb.expected_probe = rp;
    rcb.expected_kind = HDL_PROBE_KIND_REAL;
    rcb.expected_real = -2.75;
    rp.add_callback(rcb);
    fork
      begin
        rp.wait_for_change(rv, st);
        if (st != HDL_PROBE_OK || rv == null) $fatal(1, "real waiter status=%0d", st);
        if (rv.kind != HDL_PROBE_KIND_REAL || rv.r != -2.75) $fatal(1, "real waiter value mismatch");
      end
      begin
        #1ns;
        analog_value = -2.75;
      end
    join
    #1ns;
    if (rcb.calls != 1 || rp.get_change_count() != 1) $fatal(1, "real callback count mismatch");
    rp.remove_callback(rcb);
    analog_value = 4.5;
    #1ns;
    if (rcb.calls != 1 || rp.get_change_count() != 1) $fatal(1, "real callback removal failed");
    fork
      begin
        hdl_probe::wait_real_change("probe_callbacks.analog_value", typed_real);
        if (typed_real != 8.25) $fatal(1, "typed real wait mismatch");
      end
      begin
        #1ns;
        analog_value = 8.25;
      end
    join
    #1ns;
    count_before = rp.get_change_count();
    analog_value = 9.5;
    #1ns;
    if (count_before != 2 || rp.get_change_count() != count_before)
      $fatal(1, "last real waiter did not remove VPI callback");

    p.remove_callback(cb);
    observed = '0;
    #1ns;
    if (cb.calls != 1 || p.get_change_count() != 1) $fatal(1, "logic callback removal failed");
    // Duplicate registration is allowed; removal deletes only one occurrence.
    cb.expected_bits = '0;
    cb.expected_bits[32:0] = {1'bz, 32'h12345678};
    p.add_callback(cb);
    p.add_callback(cb);
    observed = {1'bz, 32'h12345678};
    #1ns;
    if (cb.calls != 3 || p.get_change_count() != 2) $fatal(1, "duplicate callback delivery mismatch");
    p.remove_callback(cb);
    cb.expected_bits = '0;
    cb.expected_bits[32:0] = 33'h100000001;
    observed = 33'h100000001;
    #1ns;
    if (cb.calls != 4 || p.get_change_count() != 3) $fatal(1, "single callback removal mismatch");
    p.remove_callback(cb);

    self_cb = new();
    self_cb.expected_probe = p;
    self_cb.expected_kind = HDL_PROBE_KIND_LOGIC4;
    self_cb.expected_bits = '0;
    self_cb.remove_self = 1;
    p.add_callback(self_cb);
    observed = '0;
    #1ns;
    if (self_cb.calls != 1 || p.get_change_count() != 4) $fatal(1, "self-removing callback failed");
    observed = 33'h7;
    #1ns;
    if (self_cb.calls != 1 || p.get_change_count() != 4) $fatal(1, "self-removal left callback active");
    fork
      begin
        hdl_probe::wait_logic_change("probe_callbacks.observed", typed_logic);
        if (typed_logic !== {{(HdlProbeMaxW-33){1'b0}}, 33'h100000005})
          $fatal(1, "typed logic wait mismatch");
      end
      begin
        #1ns;
        observed = 33'h100000005;
      end
    join
    #1ns;
    if (p.get_change_count() != 5) $fatal(1, "wait-only callback did not reconnect");
    observed = '0;
    #1ns;
    if (p.get_change_count() != 5) $fatal(1, "last logic waiter did not remove VPI callback");

    hdl_probe::cleanup();
    $display("HDL_PROBE_PASS probe_callbacks");
    $finish;
  end
endmodule
