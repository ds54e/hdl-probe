.ONESHELL:
SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.DEFAULT_GOAL := test-core
.PHONY: build-lib fmt lint lint-verible lint-slang example-core clean test-core

ROOT := $(abspath .)
BUILD_DIR := $(ROOT)/build/xezim
DPI_LIB := $(BUILD_DIR)/libhdl_probe_dpi.so
CC ?= cc
CPPFLAGS ?=
CFLAGS ?= -std=c11 -fPIC -g -Wall -Wextra -Werror
LDFLAGS ?=

# No recipes fetch or build the simulator. Supply prepared official tools.
XEZIM_SOURCE ?= $(ROOT)/tools/xezim
XEZIM ?= $(XEZIM_SOURCE)/target/release/xezim
XEZIM_INCLUDE ?= $(XEZIM_SOURCE)/include
XEZIM_FLAGS ?= --no-cache --error-exit --max-time 2us
RUN_TIMEOUT ?= 120
CHECKED_RUN := bash $(ROOT)/tests/run_checked.sh

CORE_SV := $(ROOT)/sv/hdl_probe_pkg.sv
SV_FILES := $(sort $(wildcard $(ROOT)/sv/*.sv) $(wildcard $(ROOT)/sv/*.svh) \
                  $(wildcard $(ROOT)/examples/*.sv) $(wildcard $(ROOT)/tests/*.sv))
SLANG_FILES := $(CORE_SV) $(ROOT)/examples/example_core.sv $(wildcard $(ROOT)/tests/*.sv)
CORE_TESTS := probe_values probe_callbacks probe_lifecycle

build-lib: $(DPI_LIB)

$(BUILD_DIR):
	mkdir -p "$@"

$(DPI_LIB): $(ROOT)/c/hdl_probe.c $(XEZIM_INCLUDE)/svdpi.h $(XEZIM_INCLUDE)/vpi_user.h $(XEZIM_INCLUDE)/sv_vpi_user.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I"$(XEZIM_INCLUDE)" -shared -o "$@" "$<" $(LDFLAGS)

lint:
	$(MAKE) lint-verible
	$(MAKE) lint-slang

lint-verible:
	verible-verilog-lint --rules_config=$(ROOT)/.rules.verible_lint $(SV_FILES)

lint-slang:
	# Library public methods and constructors may be unused by an example.
	slang -Weverything -Werror -Wno-unused-but-set-variable \
	  -Wno-unused-class-method -Wno-unused-constructor $(SLANG_FILES)

fmt:
	verible-verilog-format --inplace $(SV_FILES)

example-core: build-lib
	mkdir -p "$(BUILD_DIR)/example-core/tmp"
	cd "$(BUILD_DIR)/example-core"
	CC="$(CC)" TMPDIR="$$PWD/tmp" $(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log 'HDL_PROBE_PASS example_core' -- "$(XEZIM)" $(XEZIM_FLAGS) --dpi-lib "$(DPI_LIB)" -s example_core $(CORE_SV) $(ROOT)/examples/example_core.sv

# Each top is a separate process so a values failure cannot hide a callback hang.
test-core: build-lib
	status=0
	for top in $(CORE_TESTS); do
	  mkdir -p "$(BUILD_DIR)/$$top/tmp"
	  if (cd "$(BUILD_DIR)/$$top" &&
	      CC="$(CC)" TMPDIR="$$PWD/tmp" $(CHECKED_RUN) "$(RUN_TIMEOUT)" run.log "HDL_PROBE_PASS $$top" -- "$(XEZIM)" $(XEZIM_FLAGS) --dpi-lib "$(DPI_LIB)" -s "$$top" $(CORE_SV) "$(ROOT)/tests/$$top.sv"); then
	    :
	  else
	    status=1
	  fi
	done
	exit "$$status"

clean:
	rm -rf "$(BUILD_DIR)"
