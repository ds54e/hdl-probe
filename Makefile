.ONESHELL:
SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.DEFAULT_GOAL := example-all
.PHONY: build-lib fmt lint lint-verible lint-slang example-core example-uvm example-all clean \
        build-lib-xezim example-core-xezim example-uvm-xezim example-all-xezim \
        check-xezim-uvm test-core-xezim test-core-dsim

ROOT := $(abspath .)
BUILD_DIR := $(ROOT)/build
DSIM_BUILD_DIR := $(BUILD_DIR)/dsim
DSIM_HOME ?= $(HOME)/.local/lib/altairdsim/current
DSIM_LICENSE ?= $(HOME)/.config/altairdsim/dsim-license.json
DSIM_LIB := $(BUILD_DIR)/libhdl_probe_dpi.so
DSIM_UVM_OPTS := -uvm 2020.3.1 -sv_lib $(DSIM_LIB) +acc+rwcbf +UVM_NO_RELNOTES
CC := gcc
CFLAGS := -DDSIM -fPIC -g -I$(DSIM_HOME)/include

# No recipes fetch or build the simulator or UVM. Supply prepared official tools.
XEZIM_SOURCE ?= $(ROOT)/tools/xezim
XEZIM ?= $(XEZIM_SOURCE)/target/release/xezim
XEZIM_INCLUDE ?= $(XEZIM_SOURCE)/include
XEZIM_BUILD_DIR := $(BUILD_DIR)/xezim
XEZIM_LIB := $(XEZIM_BUILD_DIR)/libhdl_probe_dpi.so
XEZIM_CC ?= $(CC)
XEZIM_CFLAGS ?= -std=c11 -fPIC -g -Wall -Wextra -Werror
XEZIM_LDFLAGS ?=
XEZIM_FLAGS ?= --no-cache --error-exit --max-time 2us
UVM_SRC ?=
XEZIM_UVM_SRC ?= $(UVM_SRC)
RUN_TIMEOUT ?= 120
CHECKED_RUN := bash $(ROOT)/tests/run_checked.sh

CORE_SV := $(ROOT)/sv/hdl_probe_pkg.sv
SV_FILES := $(sort $(wildcard $(ROOT)/sv/*.sv) $(wildcard $(ROOT)/sv/*.svh) $(wildcard $(ROOT)/examples/*.sv))
SLANG_FILES := $(CORE_SV) $(ROOT)/examples/example_core.sv
CORE_TESTS := probe_values probe_callbacks probe_lifecycle

build-lib: $(DSIM_LIB)

$(BUILD_DIR) $(DSIM_BUILD_DIR) $(XEZIM_BUILD_DIR):
	mkdir -p "$@"

$(DSIM_LIB): $(ROOT)/c/hdl_probe.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -shared -o $(DSIM_LIB) $(ROOT)/c/hdl_probe.c

build-lib-xezim: $(XEZIM_LIB)

$(XEZIM_LIB): $(ROOT)/c/hdl_probe.c $(XEZIM_INCLUDE)/svdpi.h $(XEZIM_INCLUDE)/vpi_user.h $(XEZIM_INCLUDE)/sv_vpi_user.h | $(XEZIM_BUILD_DIR)
	$(XEZIM_CC) $(XEZIM_CFLAGS) -I"$(XEZIM_INCLUDE)" -shared -o "$@" "$<" $(XEZIM_LDFLAGS)

lint:
	$(MAKE) lint-verible
	$(MAKE) lint-slang

lint-verible:
	verible-verilog-lint --rules_config=$(ROOT)/.rules.verible_lint $(SV_FILES)

lint-slang:
	slang -Weverything -Werror -Wno-unused-but-set-variable $(SLANG_FILES)

fmt:
	verible-verilog-format --inplace $(SV_FILES)

example-core: build-lib
	mkdir -p "$(DSIM_BUILD_DIR)/example-core"
	cd "$(DSIM_BUILD_DIR)/example-core"
	source $(DSIM_HOME)/shell_activate.bash
	export DSIM_LICENSE=$(DSIM_LICENSE)
	$(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log 'HDL_PROBE_PASS example_core' -- dsim -sv_lib $(DSIM_LIB) +acc+rwcbf -top example_core $(CORE_SV) $(ROOT)/examples/example_core.sv

example-uvm: build-lib
	mkdir -p "$(DSIM_BUILD_DIR)/example-uvm"
	cd "$(DSIM_BUILD_DIR)/example-uvm"
	source $(DSIM_HOME)/shell_activate.bash
	export DSIM_LICENSE=$(DSIM_LICENSE)
	$(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log 'HDL_PROBE_PASS example_uvm' -- dsim $(DSIM_UVM_OPTS) -top example_uvm $(CORE_SV) $(ROOT)/examples/example_uvm.sv

example-all:
	$(MAKE) example-core
	$(MAKE) example-uvm

example-core-xezim: build-lib-xezim
	mkdir -p "$(XEZIM_BUILD_DIR)/example-core/tmp"
	cd "$(XEZIM_BUILD_DIR)/example-core"
	CC="$(XEZIM_CC)" TMPDIR="$$PWD/tmp" $(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log 'HDL_PROBE_PASS example_core' -- "$(XEZIM)" $(XEZIM_FLAGS) --dpi-lib "$(XEZIM_LIB)" -s example_core $(CORE_SV) $(ROOT)/examples/example_core.sv

check-xezim-uvm:
	@test -n "$(XEZIM_UVM_SRC)" && test -f "$(XEZIM_UVM_SRC)/uvm_pkg.sv" && test -f "$(XEZIM_UVM_SRC)/uvm_macros.svh" || { echo 'Set XEZIM_UVM_SRC (or UVM_SRC) to the prepared official UVM src directory' >&2; exit 1; }

example-uvm-xezim: check-xezim-uvm build-lib-xezim
	mkdir -p "$(XEZIM_BUILD_DIR)/example-uvm/tmp"
	cd "$(XEZIM_BUILD_DIR)/example-uvm"
	CC="$(XEZIM_CC)" TMPDIR="$$PWD/tmp" $(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log 'HDL_PROBE_PASS example_uvm' -- "$(XEZIM)" $(XEZIM_FLAGS) --dpi-lib "$(XEZIM_LIB)" -I"$(abspath $(XEZIM_UVM_SRC))" -s example_uvm "$(abspath $(XEZIM_UVM_SRC))/uvm_pkg.sv" $(CORE_SV) $(ROOT)/examples/example_uvm.sv

example-all-xezim:
	$(MAKE) example-core-xezim
	$(MAKE) example-uvm-xezim

# Each top is a separate process so a values failure cannot hide a callback hang.
test-core-xezim: build-lib-xezim
	set -euo pipefail
	status=0
	for top in $(CORE_TESTS); do
	  mkdir -p "$(XEZIM_BUILD_DIR)/$$top/tmp"
	  if (cd "$(XEZIM_BUILD_DIR)/$$top" &&
	      CC="$(XEZIM_CC)" TMPDIR="$$PWD/tmp" $(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log "HDL_PROBE_PASS $$top" -- "$(XEZIM)" $(XEZIM_FLAGS) --dpi-lib "$(XEZIM_LIB)" -s "$$top" $(CORE_SV) "$(ROOT)/tests/$$top.sv"); then
	    :
	  else
	    status=1
	  fi
	done
	exit "$$status"

test-core-dsim: build-lib
	set -eo pipefail
	source $(DSIM_HOME)/shell_activate.bash
	export DSIM_LICENSE=$(DSIM_LICENSE)
	status=0
	for top in $(CORE_TESTS); do
	  mkdir -p "$(DSIM_BUILD_DIR)/$$top"
	  if (cd "$(DSIM_BUILD_DIR)/$$top" &&
	      $(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log "HDL_PROBE_PASS $$top" -- dsim -sv_lib $(DSIM_LIB) +acc+rwcbf -top "$$top" $(CORE_SV) "$(ROOT)/tests/$$top.sv"); then
	    :
	  else
	    status=1
	  fi
	done
	exit "$$status"

clean:
	rm -rf $(BUILD_DIR) dsim.log dsim.env dsim_work metrics.db tr_db.log
