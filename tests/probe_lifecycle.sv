module probe_lifecycle;
  timeunit 1ns; timeprecision 1ps;
  import hdl_probe_pkg::*;

  logic [31:0] observed;
  logic [31:0] pending_observed;

  class counting_cb extends hdl_probe_cb;
    int calls = 0;
    logic [31:0] expected;
    virtual function void do_on_change(hdl_probe p, hdl_probe_value v);
      calls++;
      if (v == null) begin
        $fatal(1, "lifecycle callback has no value");
      end
      if (v.kind != HDL_PROBE_KIND_LOGIC4 || v.n_bits != 32 ||
          v.logic4 !== {{(HdlProbeMaxW-32){1'b0}}, expected}) begin
        $fatal(1, "lifecycle callback value mismatch");
      end
    endfunction
  endclass

  task automatic check_pending_wait(bit use_cleanup, bit prime_count);
    hdl_probe p;
    hdl_probe_value v;
    hdl_probe_status_e st;
    hdl_probe_status_e wait_status;
    counting_cb cb;
    bit completed;
    int expected_calls;

    completed = 0;
    pending_observed = '0;
    #1ns;
    p  = hdl_probe::get("probe_lifecycle.pending_observed");
    st = p.connect();
    if (st != HDL_PROBE_OK) begin
      $fatal(1, "pending waiter connect failed");
    end
    cb = new();
    cb.expected = 1;
    if (prime_count) begin
      p.add_callback(cb);
      pending_observed = 1;
      #1ns;
      if (cb.calls != 1 || p.get_change_count() != 1) begin
        $fatal(1, "pending waiter initial change failed");
      end
      p.remove_callback(cb);
    end

    fork
      begin
        p.wait_for_change(v, wait_status);
        if (wait_status != HDL_PROBE_OK || v == null) begin
          $fatal(1, "pending waiter failed status=%0d", wait_status);
        end
        if (v.kind != HDL_PROBE_KIND_LOGIC4 || v.n_bits != 32 ||
            v.logic4 !== {{(HdlProbeMaxW-32){1'b0}}, 32'd3}) begin
          $fatal(1, "pending waiter resumed with wrong value");
        end
        completed = 1;
      end
      begin
        #1ns;
        if (completed) begin
          $fatal(1, "pending waiter completed before teardown");
        end
        if (use_cleanup) begin
          hdl_probe::cleanup();
        end else begin
          p.destroy();
        end
        #1ns;
        if (completed || p.is_valid()) begin
          $fatal(1, "teardown woke pending waiter");
        end
        pending_observed = 2;
        #1ns;
        if (completed || p.is_valid()) begin
          $fatal(1, "disconnected change woke pending waiter");
        end
        st = p.connect();
        if (st != HDL_PROBE_OK) begin
          $fatal(1, "pending waiter reconnect failed");
        end
        #1ns;
        if (completed) begin
          $fatal(1, "reconnect woke pending waiter without a change");
        end
        pending_observed = 3;
      end
    join
    #1ns;
    if (!completed || p.get_change_count() != (prime_count ? 2 : 1)) begin
      $fatal(1, "pending waiter did not resume after reconnect/change");
    end

    cb.expected = 4;
    p.add_callback(cb);
    pending_observed = 4;
    #1ns;
    expected_calls = prime_count ? 2 : 1;
    if (cb.calls != expected_calls) begin
      $fatal(1, "reconnected callback failed");
    end
    hdl_probe::cleanup();
    if (p.is_valid()) begin
      $fatal(1, "cleanup missed reconnected retained probe");
    end
    pending_observed = 5;
    #1ns;
    if (cb.calls != expected_calls) begin
      $fatal(1, "cleanup left retained probe callback active");
    end
  endtask

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
    old_probe  = hdl_probe::get("probe_lifecycle.observed");
    same_probe = hdl_probe::get("probe_lifecycle.observed");
    if (old_probe != same_probe) begin
      $fatal(1, "get path cache identity mismatch");
    end
    old_cb = new();
    old_cb.expected = 32'hdeadbeef;
    // Callback demand registered before connect must be installed at connect.
    old_probe.add_callback(old_cb);
    st = old_probe.connect();
    if (st != HDL_PROBE_OK) begin
      $fatal(1, "initial connect failed status=%0d", st);
    end
    observed = 32'hdeadbeef;
    #1ns;
    if (old_cb.calls != 1 || old_probe.get_change_count() != 1) begin
      $fatal(1, "initial callback failed");
    end

    old_probe.destroy();
    old_probe.destroy();  // Idempotent; must not reuse a freed C handle.
    if (old_probe.is_valid() || old_probe.get_kind() != HDL_PROBE_KIND_UNKNOWN ||
        old_probe.get_size() != 0 || old_probe.get_change_count() != 1) begin
      $fatal(1, "destroy did not reset connection state");
    end
    observed = 32'h13579bdf;
    #1ns;
    if (old_cb.calls != 1) begin
      $fatal(1, "destroy left callback active");
    end
    // The original class retains callback registrations across destroy/reconnect.
    old_cb.expected = 32'h2468ace0;
    st = old_probe.connect();
    if (st != HDL_PROBE_OK) begin
      $fatal(1, "reconnect failed status=%0d", st);
    end
    observed = 32'h2468ace0;
    #1ns;
    if (old_cb.calls != 2 || old_probe.get_change_count() != 2) begin
      $fatal(1, "reconnect callback failed");
    end

    hdl_probe::cleanup();
    hdl_probe::cleanup();
    if (old_probe.is_valid() || hdl_probes_by_path.num() != 0 ||
        hdl_probes_by_key.num() != 0 || hdl_probe_next_sv_key != 0) begin
      $fatal(1, "cleanup did not fully reset caches/keys");
    end
    observed = 32'h11223344;
    #1ns;
    if (old_cb.calls != 2) begin
      $fatal(1, "cleanup left callback active");
    end

    new_probe = hdl_probe::get("probe_lifecycle.observed");
    if (new_probe == old_probe) begin
      $fatal(1, "cleanup retained path cache");
    end
    new_cb = new();
    new_cb.expected = 32'h89abcdef;
    new_probe.add_callback(new_cb);
    st = new_probe.read(v);
    if (st != HDL_PROBE_OK || v == null) begin
      $fatal(1, "post-cleanup read failed status=%0d", st);
    end
    if (v.logic4 !== {{(HdlProbeMaxW - 32) {1'b0}}, 32'h11223344}) begin
      $fatal(1, "post-cleanup value mismatch");
    end
    if (hdl_probe_next_sv_key != 1) begin
      $fatal(1, "post-cleanup key mismatch");
    end
    fork
      begin
        new_probe.wait_for_change(v, st);
        if (st != HDL_PROBE_OK || v == null) begin
          $fatal(1, "post-cleanup wait failed status=%0d", st);
        end
        if (v.logic4 !== {{(HdlProbeMaxW - 32) {1'b0}}, 32'h89abcdef}) begin
          $fatal(1, "post-cleanup waiter value mismatch");
        end
      end
      begin
        #1ns;
        observed = 32'h89abcdef;
      end
    join
    #1ns;
    if (new_cb.calls != 1 || old_cb.calls != 2 || new_probe.get_change_count() != 1) begin
      $fatal(1, "stale callback/key routed after cleanup");
    end
    new_probe.remove_callback(new_cb);
    hdl_probe::cleanup();
    check_pending_wait(0, 0);
    check_pending_wait(0, 1);
    check_pending_wait(1, 0);
    check_pending_wait(1, 1);
    $display("HDL_PROBE_PASS probe_lifecycle");
    $finish;
  end
endmodule
