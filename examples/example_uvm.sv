module example_uvm;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  import hdl_probe_pkg::*;
  `include "uvm_macros.svh"

  logic [3:0] observed;
  real analog_value;

  initial begin : watchdog
    #100ns;
    $fatal(1, "example_uvm timeout");
  end

  initial begin : stimulus
    observed = 4'h0;
    analog_value = 0.5;
    #10ns observed = 4'h9;
    #10ns analog_value = 1.25;
  end

  initial begin : test
    logic [3:0] bits;
    real real_value;

    #1ns;
    if (!hdl_probe::read_logic("example_uvm.observed", bits)) begin
      `uvm_fatal("EXAMPLE", "initial hdl_probe::read_logic failed")
    end
    if (bits !== 4'h0) begin
      `uvm_fatal("EXAMPLE", $sformatf("initial logic mismatch value=0x%0h", bits))
    end

    if (!hdl_probe::read_real("example_uvm.analog_value", real_value)) begin
      `uvm_fatal("EXAMPLE", "initial hdl_probe::read_real failed")
    end
    if (real_value != 0.5) begin
      `uvm_fatal("EXAMPLE", $sformatf("initial real mismatch value=%f", real_value))
    end

    hdl_probe::wait_logic_change("example_uvm.observed", bits);
    if (bits !== 4'h9) begin
      `uvm_fatal("EXAMPLE", $sformatf("logic wait mismatch value=0x%0h", bits))
    end

    hdl_probe::wait_real_change("example_uvm.analog_value", real_value);
    if (real_value != 1.25) begin
      `uvm_fatal("EXAMPLE", $sformatf("real wait mismatch value=%f", real_value))
    end

    `uvm_info("EXAMPLE", "example_uvm passed", UVM_NONE)
    hdl_probe::cleanup();
    $display("HDL_PROBE_PASS example_uvm");
    #1ns;
    $finish;
  end
endmodule
