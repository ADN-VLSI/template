HAS_SUBMODULES = 1

export ADN_TEMPLATE=$(CURDIR)
export REPO_NAME_EXP=ADN_TEMPLATE

export ADN_COMMON=$(REPO_ROOT)/submodule/adn_common

.PHONY: compile_all_submodules
compile_all_submodules:
	@make -s compile_submodule SUB=adn_common
