package hdl_probe_pkg;
  timeunit 1ns; timeprecision 1ps;

  typedef class hdl_probe;
  typedef class hdl_probe_value;
  typedef class hdl_probe_cb;

  localparam int unsigned HdlProbeMaxW = 1024;

  // Keep status values in sync with c/hdl_probe.c.
  typedef enum int {
    HDL_PROBE_OK = 0,
    HDL_PROBE_NOT_FOUND = 1,
    HDL_PROBE_UNSUPPORTED_KIND = 2,
    HDL_PROBE_TOO_WIDE = 3,
    HDL_PROBE_READ_ERROR = 4,
    HDL_PROBE_INTERNAL_ERROR = 5
  } hdl_probe_status_e;

  // Keep kind values in sync with c/hdl_probe.c.
  typedef enum int {
    HDL_PROBE_KIND_UNKNOWN = 0,
    HDL_PROBE_KIND_LOGIC4 = 1,
    HDL_PROBE_KIND_REAL = 2
  } hdl_probe_kind_e;

  import "DPI-C" context function chandle hdl_probe_dpi_create(
    input string path,
    input int sv_key,
    output int status
  );
  import "DPI-C" context function int hdl_probe_dpi_destroy(input chandle hnd);
  import "DPI-C" context function int hdl_probe_dpi_set_enable_callback(
    input chandle hnd,
    input int enable
  );
  import "DPI-C" context function int hdl_probe_dpi_get_kind(input chandle hnd);
  import "DPI-C" context function int hdl_probe_dpi_get_size(input chandle hnd);
  import "DPI-C" context function int hdl_probe_dpi_read_logic(
    input chandle hnd,
    output logic [HdlProbeMaxW-1:0] value
  );
  import "DPI-C" context function int hdl_probe_dpi_read_real(
    input chandle hnd,
    output real value
  );

  hdl_probe hdl_probes_by_path[string];
  hdl_probe hdl_probes_by_key[int];
  int hdl_probe_next_sv_key = 0;

  class hdl_probe_value;
    hdl_probe_kind_e kind;
    int unsigned n_bits;
    logic [HdlProbeMaxW-1:0] logic4;
    real r;

    function new();
      clear();
    endfunction

    function void clear();
      kind = HDL_PROBE_KIND_UNKNOWN;
      n_bits = 0;
      logic4 = '0;
      r = 0.0;
    endfunction

    function void copy_from(hdl_probe_value rhs);
      if (rhs == null) begin
        clear();
        return;
      end

      kind = rhs.kind;
      n_bits = rhs.n_bits;
      logic4 = rhs.logic4;
      r = rhs.r;
    endfunction

    function bit get_logic(output logic [HdlProbeMaxW-1:0] value, output int unsigned width);
      value = '0;
      width = 0;
      if (kind != HDL_PROBE_KIND_LOGIC4) begin
        return 0;
      end

      value = logic4;
      width = n_bits;
      return 1;
    endfunction

    function bit get_real(output real value);
      value = 0.0;
      if (kind != HDL_PROBE_KIND_REAL) begin
        return 0;
      end

      value = r;
      return 1;
    endfunction
  endclass

  virtual class hdl_probe_cb;
    function new();
    endfunction

    // Each notification shares one value; mutations affect later callbacks.
    virtual function void do_on_change(hdl_probe p, hdl_probe_value v);
    endfunction
  endclass

  class hdl_probe;
    protected string m_path;
    protected chandle m_handle;
    protected hdl_probe_kind_e m_kind;
    protected int unsigned m_n_bits;
    protected int m_sv_key;
    protected int unsigned m_change_count;
    protected int unsigned m_active_waiters;
    protected bit m_callback_enabled;
    protected hdl_probe_cb m_callbacks[$];

    function new(string path = "");
      m_path = path;
      m_handle = null;
      m_kind = HDL_PROBE_KIND_UNKNOWN;
      m_n_bits = 0;
      m_sv_key = -1;
      m_change_count = 0;
      m_active_waiters = 0;
      m_callback_enabled = 0;
    endfunction

    protected function void m_reset_connect_state();
      if (m_sv_key >= 0 && hdl_probes_by_key.exists(
              m_sv_key
          ) && hdl_probes_by_key[m_sv_key] == this) begin
        hdl_probes_by_key.delete(m_sv_key);
      end
      m_handle = null;
      m_kind = HDL_PROBE_KIND_UNKNOWN;
      m_n_bits = 0;
      m_sv_key = -1;
      m_callback_enabled = 0;
    endfunction

    protected function automatic bit m_has_callback_demand();
      return (m_active_waiters != 0) || (m_callbacks.size() != 0);
    endfunction

    protected function automatic hdl_probe_status_e m_update_callback_state();
      bit want_enabled;

      if (m_handle == null) begin
        return HDL_PROBE_OK;
      end

      want_enabled = m_has_callback_demand();
      if (want_enabled == m_callback_enabled) begin
        return HDL_PROBE_OK;
      end

      if (!hdl_probe_dpi_set_enable_callback(m_handle, want_enabled ? 1 : 0)) begin
        return HDL_PROBE_INTERNAL_ERROR;
      end

      m_callback_enabled = want_enabled;
      return HDL_PROBE_OK;
    endfunction

    function void destroy();
      if (m_handle != null) begin
        void'(hdl_probe_dpi_destroy(m_handle));
      end
      m_reset_connect_state();
    endfunction

    static function hdl_probe get(string path);
      if (!hdl_probes_by_path.exists(path)) begin
        hdl_probes_by_path[path] = new(path);
      end
      return hdl_probes_by_path[path];
    endfunction

    static function bit read_logic(string path, output logic [HdlProbeMaxW-1:0] value);
      hdl_probe probe;
      hdl_probe_value v;
      hdl_probe_status_e st;

      value = '0;
      probe = get(path);
      st = probe.read(v);
      if (st != HDL_PROBE_OK || v == null || v.kind != HDL_PROBE_KIND_LOGIC4) begin
        return 0;
      end

      value = v.logic4;
      return 1;
    endfunction

    static function bit read_real(string path, output real value);
      hdl_probe probe;
      hdl_probe_value v;
      hdl_probe_status_e st;

      value = 0.0;
      probe = get(path);
      st = probe.read(v);
      if (st != HDL_PROBE_OK || v == null || v.kind != HDL_PROBE_KIND_REAL) begin
        return 0;
      end

      value = v.r;
      return 1;
    endfunction

    static task wait_logic_change(string path, output logic [HdlProbeMaxW-1:0] value);
      hdl_probe probe;
      hdl_probe_value v;
      hdl_probe_status_e st;

      value = '0;
      probe = get(path);
      probe.wait_for_change(v, st);
      if (st != HDL_PROBE_OK) begin
        $fatal(1, "hdl_probe: wait_logic_change(%s) failed: %s", path, st.name());
      end else if (v == null || v.kind != HDL_PROBE_KIND_LOGIC4) begin
        $fatal(1, "hdl_probe: wait_logic_change(%s) kind mismatch", path);
      end else begin
        value = v.logic4;
      end
    endtask

    static task wait_real_change(string path, output real value);
      hdl_probe probe;
      hdl_probe_value v;
      hdl_probe_status_e st;

      value = 0.0;
      probe = get(path);
      probe.wait_for_change(v, st);
      if (st != HDL_PROBE_OK) begin
        $fatal(1, "hdl_probe: wait_real_change(%s) failed: %s", path, st.name());
      end else if (v == null || v.kind != HDL_PROBE_KIND_REAL) begin
        $fatal(1, "hdl_probe: wait_real_change(%s) kind mismatch", path);
      end else begin
        value = v.r;
      end
    endtask

    static function void cleanup();
      int key;

      while (hdl_probes_by_key.first(
          key
      ) != 0) begin
        if (hdl_probes_by_key[key] != null) begin
          hdl_probes_by_key[key].destroy();
        end
        hdl_probes_by_key.delete(key);
      end
      hdl_probes_by_path.delete();
      hdl_probes_by_key.delete();
      hdl_probe_next_sv_key = 0;
    endfunction

    function hdl_probe_status_e connect();
      int c_status;
      int raw_n_bits;
      hdl_probe_status_e ret_status;

      if (m_handle != null) begin
        return HDL_PROBE_OK;
      end

      c_status = HDL_PROBE_INTERNAL_ERROR;
      m_sv_key = hdl_probe_next_sv_key;
      hdl_probe_next_sv_key++;

      m_handle   = hdl_probe_dpi_create(m_path, m_sv_key, c_status);
      ret_status = hdl_probe_status_e'(c_status);
      if (m_handle == null || ret_status != HDL_PROBE_OK) begin
        m_reset_connect_state();
        return ret_status;
      end

      m_kind = hdl_probe_kind_e'(hdl_probe_dpi_get_kind(m_handle));
      raw_n_bits = hdl_probe_dpi_get_size(m_handle);
      if (raw_n_bits < 0) begin
        ret_status = HDL_PROBE_INTERNAL_ERROR;
        destroy();
        return ret_status;
      end
      m_n_bits = raw_n_bits[31:0];

      if (m_kind == HDL_PROBE_KIND_LOGIC4 && m_n_bits > HdlProbeMaxW) begin
        ret_status = HDL_PROBE_TOO_WIDE;
        destroy();
        return ret_status;
      end

      hdl_probes_by_key[m_sv_key] = this;
      ret_status = m_update_callback_state();
      if (ret_status != HDL_PROBE_OK) begin
        destroy();
        return ret_status;
      end

      return HDL_PROBE_OK;
    endfunction

    function bit is_valid();
      return m_handle != null;
    endfunction

    function string get_path();
      return m_path;
    endfunction

    function hdl_probe_kind_e get_kind();
      return m_kind;
    endfunction

    function int unsigned get_size();
      return m_n_bits;
    endfunction

    function int unsigned get_change_count();
      return m_change_count;
    endfunction

    function void add_callback(hdl_probe_cb cb);
      hdl_probe_status_e st;

      if (cb != null) begin
        m_callbacks.push_back(cb);
        st = m_update_callback_state();
        if (st != HDL_PROBE_OK) begin
          $warning("hdl_probe: add_callback(%s) callback sync failed: %s", m_path, st.name());
        end
      end
    endfunction

    function void remove_callback(hdl_probe_cb cb);
      hdl_probe_status_e st;

      foreach (m_callbacks[i]) begin
        if (m_callbacks[i] == cb) begin
          m_callbacks.delete(i);
          break;
        end
      end

      st = m_update_callback_state();
      if (st != HDL_PROBE_OK) begin
        $warning("hdl_probe: remove_callback(%s) callback sync failed: %s", m_path, st.name());
      end
    endfunction

    function hdl_probe_status_e read(ref hdl_probe_value v);
      hdl_probe_status_e st;
      real r_value;

      st = connect();
      if (st != HDL_PROBE_OK) begin
        return st;
      end

      if (v == null) begin
        v = new();
      end

      v.clear();
      v.kind   = m_kind;
      v.n_bits = m_n_bits;

      case (int'(m_kind))
        int'(HDL_PROBE_KIND_LOGIC4): begin
          if (!hdl_probe_dpi_read_logic(m_handle, v.logic4)) begin
            return HDL_PROBE_READ_ERROR;
          end
          return HDL_PROBE_OK;
        end

        int'(HDL_PROBE_KIND_REAL): begin
          if (!hdl_probe_dpi_read_real(m_handle, r_value)) begin
            return HDL_PROBE_READ_ERROR;
          end
          v.r = r_value;
          return HDL_PROBE_OK;
        end

        default: begin
          return HDL_PROBE_UNSUPPORTED_KIND;
        end
      endcase
    endfunction

    task wait_for_change(ref hdl_probe_value v, ref hdl_probe_status_e st);
      int unsigned previous_change_count;

      st = connect();
      if (st != HDL_PROBE_OK) begin
        return;
      end

      m_active_waiters++;
      st = m_update_callback_state();
      if (st != HDL_PROBE_OK) begin
        m_active_waiters--;
        void'(m_update_callback_state());
        return;
      end

      previous_change_count = m_change_count;
      wait (m_change_count != previous_change_count);

      m_active_waiters--;

      st = m_update_callback_state();
      if (st != HDL_PROBE_OK) begin
        return;
      end

      st = read(v);
    endtask

    function void m_dpi_notify_change();
      hdl_probe_value value;
      hdl_probe_cb callback_snapshot[$];

      m_change_count++;

      if (m_callbacks.size() == 0) begin
        return;
      end

      value = null;
      if (read(value) != HDL_PROBE_OK) begin
        return;
      end

      callback_snapshot = m_callbacks;
      foreach (callback_snapshot[i]) begin
        if (callback_snapshot[i] != null) begin
          callback_snapshot[i].do_on_change(this, value);
        end
      end
    endfunction
  endclass

  export "DPI-C" function hdl_probe_value_change_notify;

  function automatic void hdl_probe_value_change_notify(int sv_key);
    if (hdl_probes_by_key.exists(sv_key)) begin
      hdl_probes_by_key[sv_key].m_dpi_notify_change();
    end
  endfunction

endpackage
