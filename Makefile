export SHELL=/bin/bash

include ext.mk

####################################################################################################
# Variables
####################################################################################################

export REPO_FILE_EXT=$(shell echo $(REPO_NAME_EXP) | tr '[:upper:]' '[:lower:]')

REPO_ROOT := $(CURDIR)

BUILD_DIR := $(REPO_ROOT)/build
LOG_DIR := $(REPO_ROOT)/log
COVERAGE_DIR := $(REPO_ROOT)/coverage
DOCUMENTER := $(REPO_ROOT)/submodule/documenter
SOURCE_DOC_DIR := $(REPO_ROOT)/document/source

TN    := default
TC    := 1
GUI   := 0
VCD   := 0
DEBUG := 0

####################################################################################################
# Tools
####################################################################################################

XVLOG  ?= xvlog
XELAB  ?= xelab
XSIM   ?= xsim
PYTHON ?= python

####################################################################################################
# Macros
####################################################################################################

O_EW :=  | (grep -iE "Error|Warning" --color=auto || true)
H_EW :=  | (grep -iE "Error|Warning|" --color=auto)

LINE_1 := This file is part of https://github.com/ADN-VLSI/$(REPO_FILE_EXT)
LINE_2 := Copyright (c) $(shell date +%Y) ADN Semiconductors
LINE_3 := Licensed under the MIT License
LINE_4 := See LICENSE file in the project root for full license information

####################################################################################################
# VIVADO
####################################################################################################

$(BUILD_DIR) $(LOG_DIR) $(COVERAGE_DIR):
	@echo -e "\033[1;33m#\033[0m Creating directory $@"
	@mkdir -p $@
	@echo "*" > $@/.gitignore

.PHONY: clean
clean:
	@echo -e "\033[1;33m#\033[0m Cleaning build directory"
	@rm -rf $(BUILD_DIR)

.PHONY: clean_full
clean_full:
	@make -s clean
	@echo -e "\033[1;33m#\033[0m Cleaning log directories"
	@rm -rf $(LOG_DIR)
	@echo -e "\033[1;33m#\033[0m Cleaning coverage directories"
	@rm -rf $(COVERAGE_DIR)

.PHONY: $(REPO_ROOT)/reuse.f
$(REPO_ROOT)/reuse.f:
	@git submodule update --init --depth 1
	@echo -e "\033[1;33m#\033[0m Generating Reusable IP Filelist"
	@echo "-i $(REPO_ROOT)/include" > $(REPO_ROOT)/reuse.f
ifeq ($(HAS_SUBMODULES), 1)
	@((cat $$(find $(REPO_ROOT)/submodule -mindepth 2 -maxdepth 2 -name "reuse.f") || true) | grep -E "^-i " ) >> $(REPO_ROOT)/reuse.f
endif
	@find $(REPO_ROOT)/interface -maxdepth 1 -name "*.sv" >> $(REPO_ROOT)/reuse.f
	@find $(REPO_ROOT)/source -maxdepth 1 -name "*.sv" >> $(REPO_ROOT)/reuse.f
	@sed -i 's|$(REPO_ROOT)|$$\{$(REPO_NAME_EXP)\}|g' $(REPO_ROOT)/reuse.f
	@sort -u $(REPO_ROOT)/reuse.f > $(REPO_ROOT)/reuse2.f
	@mv $(REPO_ROOT)/reuse2.f $(REPO_ROOT)/reuse.f

.PHONY: $(REPO_ROOT)/local.f
$(REPO_ROOT)/local.f:
	@echo -e "\033[1;33m#\033[0m Generating Testbench Filelist"
	@echo "-i $(REPO_ROOT)/testbench" > $(REPO_ROOT)/local.f
	@find $(REPO_ROOT)/testbench -maxdepth 1 -name "*.sv" >> $(REPO_ROOT)/local.f
	@sed -i 's|$(REPO_ROOT)|$$\{$(REPO_NAME_EXP)\}|g' $(REPO_ROOT)/local.f

.PHONY: $(BUILD_DIR)/XSIM_ARGS
$(BUILD_DIR)/XSIM_ARGS:
ifeq ($(GUI), 0)
	@echo "-runall" > $@
else
	@echo "-gui --autoloadwcfg --view $(REPO_ROOT)/wcfg/$(TOP).wcfg" > $@
endif
	@echo "--testplusarg TN=$(TN)" >> $@
	@echo "--testplusarg TC=$(TC)" >> $@
	@echo "--testplusarg VCD=$(VCD)" >> $@
	@echo "--testplusarg DEBUG=$(DEBUG)" >> $@

.PHONY: compile_all
compile_all:
	@make -s compile_all_submodules
	@make -s compile_this_module

.PHONY: get_hash
get_hash:
	@touch $(BUILD_DIR)/hash_old
	@$(eval var = $(shell grep -E "^-i " $(REPO_ROOT)/reuse.f | sed "s/-i //g" || echo ""))
	@if [ -n "$(var)" ]; then find $(var) -type f > $(BUILD_DIR)/build_list; fi
	@$(eval var = $(shell grep -E "^-i " $(REPO_ROOT)/local.f | sed "s/-i //g" || echo ""))
	@if [ -n "$(var)" ]; then find $(var) -type f >> $(BUILD_DIR)/build_list; fi
	@$(eval var = $(shell cat $(REPO_ROOT)/reuse.f | sed "s/^-i .*//g"))
	@$(foreach file, $(var), echo $(file) >> $(BUILD_DIR)/build_list;)
	@$(eval var = $(shell cat $(REPO_ROOT)/local.f | sed "s/^-i .*//g"))
	@$(foreach file, $(var), echo $(file) >> $(BUILD_DIR)/build_list;)
	@xargs -a $(BUILD_DIR)/build_list sha512sum > $(BUILD_DIR)/hash_new

.PHONY: compile_this_module
compile_this_module:
	@make -s get_hash
	@if cmp -s $(BUILD_DIR)/hash_old $(BUILD_DIR)/hash_new; then \
		echo -e "\033[1;33m#\033[0m Source files have not changed, skipping compilation."; \
	else \
		echo -e "\033[1;33m#\033[0m Source files have changed, recompiling..."; \
		cd $(BUILD_DIR) && $(XVLOG) -sv -f $(REPO_ROOT)/reuse.f -f $(REPO_ROOT)/local.f -log $(LOG_DIR)/xvlog_$(shell date +%Y%m%d_%H%M%S).log $(O_EW); \
		cp $(BUILD_DIR)/hash_new $(BUILD_DIR)/hash_old; \
		rm -rf $(BUILD_DIR)/xelab_*; \
	fi

# Elaborate
$(BUILD_DIR)/xelab_$(TOP):
	@echo -e "\033[1;33m#\033[0m Elaborating $(TOP)"
	@cd $(BUILD_DIR) && $(XELAB) $(TOP) -s snap_$(TOP) -debug all -log $(LOG_DIR)/xelab_$(TOP)_$(shell date +%Y%m%d_%H%M%S).log $(O_EW)
	@echo "" > $(BUILD_DIR)/xelab_$(TOP)

.PHONY: __ENV_BUILD__
__ENV_BUILD__:
	@make -s $(BUILD_DIR)
	@make -s $(LOG_DIR)
	@make -s $(REPO_ROOT)/reuse.f
	@make -s $(REPO_ROOT)/local.f
	@make -s compile_all
	@make -s $(BUILD_DIR)/xelab_$(TOP)

.PHONY: simulate
simulate:
	@make -s __ENV_BUILD__ TOP=$(TOP)
	@make -s $(BUILD_DIR)/XSIM_ARGS GUI=$(GUI) TN=$(TN) TC=$(TC) VCD=$(VCD) DEBUG=$(DEBUG)
	@echo -e "\033[1;33m#\033[0m Simulating TOP:$(TOP) Test:$(TN) Count:$(TC)"
	@cd $(BUILD_DIR) && $(XSIM) snap_$(TOP) -f $(BUILD_DIR)/XSIM_ARGS -log $(LOG_DIR)/xsim_$(TOP)_$(TN)_$(shell date +%Y%m%d_%H%M%S).log $(H_EW)
ifneq ($(VCD), 0)
	@echo -e "\033[1;33m#\033[0m Loading VCD waveform file"
	@gtkwave $(REPO_ROOT)/wcfg/$(TOP).gtkw || gtkwave $(BUILD_DIR)/$(TOP).vcd
endif

.PHONY: compile_submodule
compile_submodule: 
	@make -s $(BUILD_DIR)
	@make -s $(LOG_DIR)
	@touch $(BUILD_DIR)/$(SUB)_commit
	@SUB_HASH=$$(git -C $(REPO_ROOT)/submodule/$(SUB) rev-parse HEAD 2>/dev/null || echo ""); \
	FILE_HASH=$$(cat $(BUILD_DIR)/$(SUB)_commit 2>/dev/null || echo ""); \
	if [ "$$SUB_HASH" != "$$FILE_HASH" ] || [ -z "$$SUB_HASH" ]; then \
		echo -e "\033[1;33m#\033[0m Submodule $(SUB) commit has changed, recompiling..."; \
		echo -n $(shell git submodule status $(REPO_ROOT)/submodule/$(SUB) | awk '{print $$1}') > $(BUILD_DIR)/$(SUB)_commit; \
		cd $(BUILD_DIR) && $(XVLOG) -sv -f $(REPO_ROOT)/submodule/$(SUB)/reuse.f -log $(LOG_DIR)/xvlog_$(SUB)_$(shell date +%Y%m%d_%H%M%S).log $(O_EW); \
		git submodule status $(REPO_ROOT)/submodule/$(SUB) | awk '{print $$1}' > $(BUILD_DIR)/$(SUB)_commit; \
		rm -f $(BUILD_DIR)/xelab_*; \
	else \
		echo -e "\033[1;33m#\033[0m Submodule $(SUB) commit has not changed, skipping compilation."; \
	fi

.PHONY: regression
regression:
	@./.github/regression.sh

####################################################################################################
# UPDATE DOC LIST
####################################################################################################

.PHONY: update_doc_list
update_doc_list:
	@make -s $(REPO_ROOT)/reuse.f
	@make -s create_all_docs
	@cat readme_base.md > readme.md
	@echo "" >> readme.md
	@echo "## RTL" >> readme.md
	@$(foreach file, $(shell find $(SOURCE_DOC_DIR) -name "*.md"), make -s get_source_doc_header FILE=$(file);)
	@echo "" >> readme.md

.PHONY: create_all_docs
create_all_docs:
	@make -s clean_all_docs
	@$(foreach file, $(shell find $(REPO_ROOT)/source/ -type f -name "*.sv"), make -s gen_doc FILE=$(file);)

.PHONY: clean_all_docs
clean_all_docs:
	@mkdir -p $(SOURCE_DOC_DIR)
	@rm -f $(SOURCE_DOC_DIR)/*.md
	@rm -f $(SOURCE_DOC_DIR)/*_top.svg

.PHONY: get_source_doc_header
get_source_doc_header:
	@$(eval HEADER := $(shell cat $(FILE) | grep -E "# " | sed "s/^# //g" | sed "s/ .*//g"))
	@echo -n "[\`$(HEADER)" | sed "s/ .*/\`\]\(/g" >> readme.md
	@echo -n "$(FILE)" | sed "s|$(REPO_ROOT)/||g" >> readme.md
	@echo ")" >> readme.md

.PHONY: gen_doc
gen_doc:
	@echo "Creating document for $(FILE)"
	@$(PYTHON) $(DOCUMENTER)/sv_documenter.py $(FILE) $(SOURCE_DOC_DIR)
	@sed -i "s|.*${LINE_1}.*|<br>**${LINE_1}**|g" $(SOURCE_DOC_DIR)/$(shell basename $(FILE) | sed "s/\.sv/\.md/g")
	@sed -i "s|.*${LINE_2}.*|<br>**${LINE_2}**|g" $(SOURCE_DOC_DIR)/$(shell basename $(FILE) | sed "s/\.sv/\.md/g")
	@sed -i "s|.*${LINE_3}.*|<br>**${LINE_3}**|g" $(SOURCE_DOC_DIR)/$(shell basename $(FILE) | sed "s/\.sv/\.md/g")
	@sed -i "s|.*${LINE_4}.*|<br>**${LINE_4}**|g" $(SOURCE_DOC_DIR)/$(shell basename $(FILE) | sed "s/\.sv/\.md/g")

####################################################################################################
# TESTBENCH & SOURCE GENERATION
####################################################################################################

.PHONY: gen_source
gen_source:
# if file doesn't exist, generate it
	@if [ ! -f $(REPO_ROOT)/source/$(RTL).sv ]; then \
		echo -e "\033[1;33m#\033[0m Generating source for $(RTL)"; \
		cp $(DOCUMENTER)/source.sv $(REPO_ROOT)/source/$(RTL).sv; \
		sed -i "s|nemotron|foez---bhai|g" $(REPO_ROOT)/source/$(RTL).sv; \
		sed -i "s|__AUTHOR_NAME__|$$(git config user.name)|g" $(REPO_ROOT)/source/$(RTL).sv; \
		sed -i "s|__AUTHOR_EMAIL__|$$(git config user.email)|g" $(REPO_ROOT)/source/$(RTL).sv; \
		sed -i "s|squared-studio/__REPO_NAME__|ADN-VLSI/$(REPO_FILE_EXT)|g" $(REPO_ROOT)/source/$(RTL).sv; \
		sed -i "s|__YEAR__ squared-studio|$$(date +%Y) ADN Semiconductors|g" $(REPO_ROOT)/source/$(RTL).sv; \
		sed -i "s|source_model|$(RTL)|g" $(REPO_ROOT)/source/$(RTL).sv; \
	fi
	@code $(REPO_ROOT)/source/$(RTL).sv

.PHONY: gen_testbench
gen_testbench:
# if file doesn't exist, generate it
	@if [ ! -f $(REPO_ROOT)/testbench/$(TOP).sv ]; then \
		echo -e "\033[1;33m#\033[0m Generating testbench for $(TOP)"; \
		cp $(DOCUMENTER)/testbench.sv $(REPO_ROOT)/testbench/$(TOP).sv; \
		sed -i "s|nemotron|foez---bhai|g" $(REPO_ROOT)/testbench/$(TOP).sv; \
		sed -i "s|__AUTHOR_NAME__|$$(git config user.name)|g" $(REPO_ROOT)/testbench/$(TOP).sv; \
		sed -i "s|__AUTHOR_EMAIL__|$$(git config user.email)|g" $(REPO_ROOT)/testbench/$(TOP).sv; \
		sed -i "s|squared-studio/__REPO_NAME__|ADN-VLSI/$(REPO_FILE_EXT)|g" $(REPO_ROOT)/testbench/$(TOP).sv; \
		sed -i "s|__YEAR__ squared-studio|$$(date +%Y) ADN Semiconductors|g" $(REPO_ROOT)/testbench/$(TOP).sv; \
		sed -i "s|testbench_model|$(TOP)|g" $(REPO_ROOT)/testbench/$(TOP).sv; \
		sed -i "s|tb_ess.sv|adn_common_tb_headers.sv|g" $(REPO_ROOT)/testbench/$(TOP).sv; \
	fi
	@code $(REPO_ROOT)/testbench/$(TOP).sv
