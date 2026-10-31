module probe_lifecycle;
  timeunit 1ns;
  timeprecision 1ps;
  import hdl_probe_pkg::*;

  logic [31:0] observed;

  class counting_cb extends hdl_probe_cb;
    int calls = 0;
    logic [31:0] expected;
    virtual function void do_on_change(hdl_probe p, hdl_probe_value v);
      calls++;
      if (v == null) $fatal(1, "lifecycle callback has no value");
      if (v.kind != HDL_PROBE_KIND_LOGIC4 || v.n_bits != 32 ||
          v.logic4 !== {{(HdlProbeMaxW-32){1'b0}}, expected})
        $fatal(1, "lifecycle callback value mismatch");
    endfunction
  endclass

  initial begin : watchdog
    #500ns;
    $fatal(1, "probe_lifecycle timeout");
  end

  initial begin : test
    hdl_probe old_probe;
    hdl_probe new_probe;
    hdl_probe same_probe;
    hdl_probe_value v;
    hdl_probe_status_e st;
    counting_cb old_cb;
    counting_cb new_cb;

    observed = '0;
    #1ns;
    old_probe = hdl_probe::get("probe_lifecycle.observed");
    same_probe = hdl_probe::get("probe_lifecycle.observed");
    if (old_probe != same_probe) $fatal(1, "get path cache identity mismatch");
    old_cb = new();
    old_cb.expected = 32'hdeadbeef;
    // Callback demand registered before connect must be installed at connect.
    old_probe.add_callback(old_cb);
    st = old_probe.connect();
    if (st != HDL_PROBE_OK) $fatal(1, "initial connect failed status=%0d", st);
    observed = 32'hdeadbeef;
    #1ns;
    if (old_cb.calls != 1 || old_probe.get_change_count() != 1) $fatal(1, "initial callback failed");

    old_probe.destroy();
    old_probe.destroy();  // Idempotent; must not reuse a freed C handle.
    if (old_probe.is_valid() || old_probe.get_kind() != HDL_PROBE_KIND_UNKNOWN ||
        old_probe.get_size() != 0 || old_probe.get_change_count() != 0)
      $fatal(1, "destroy did not reset connection state");
    observed = 32'h13579bdf;
    #1ns;
    if (old_cb.calls != 1) $fatal(1, "destroy left callback active");
    // The original class retains callback registrations across destroy/reconnect.
    old_cb.expected = 32'h2468ace0;
    st = old_probe.connect();
    if (st != HDL_PROBE_OK) $fatal(1, "reconnect failed status=%0d", st);
    observed = 32'h2468ace0;
    #1ns;
    if (old_cb.calls != 2 || old_probe.get_change_count() != 1) $fatal(1, "reconnect callback failed");

    hdl_probe::cleanup();
    hdl_probe::cleanup();
    if (old_probe.is_valid() || hdl_probes_by_path.num() != 0 ||
        hdl_probes_by_key.num() != 0 || hdl_probe_next_sv_key != 0)
      $fatal(1, "cleanup did not fully reset caches/keys");
    observed = 32'h11223344;
    #1ns;
    if (old_cb.calls != 2) $fatal(1, "cleanup left callback active");

    new_probe = hdl_probe::get("probe_lifecycle.observed");
    if (new_probe == old_probe) $fatal(1, "cleanup retained path cache");
    new_cb = new();
    new_cb.expected = 32'h89abcdef;
    new_probe.add_callback(new_cb);
    st = new_probe.read(v);
    if (st != HDL_PROBE_OK || v == null) $fatal(1, "post-cleanup read failed status=%0d", st);
    if (v.logic4 !== {{(HdlProbeMaxW-32){1'b0}}, 32'h11223344} ||
        hdl_probe_next_sv_key != 1)
      $fatal(1, "post-cleanup key/value mismatch");
    fork
      begin
        new_probe.wait_for_change(v, st);
        if (st != HDL_PROBE_OK || v == null) $fatal(1, "post-cleanup wait failed status=%0d", st);
        if (v.logic4 !== {{(HdlProbeMaxW-32){1'b0}}, 32'h89abcdef})
          $fatal(1, "post-cleanup waiter value mismatch");
      end
      begin
        #1ns;
        observed = 32'h89abcdef;
      end
    join
    #1ns;
    if (new_cb.calls != 1 || old_cb.calls != 2 || new_probe.get_change_count() != 1)
      $fatal(1, "stale callback/key routed after cleanup");
    new_probe.remove_callback(new_cb);
    hdl_probe::cleanup();
    $display("HDL_PROBE_PASS probe_lifecycle");
    $finish;
  end
endmodule
