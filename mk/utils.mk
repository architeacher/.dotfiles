define displayProjectLogo
    # http://patorjk.com/software/taag/#p=testall&f=Slant&t=.dotfiles
    printf "${1}"
    cat assets/logo.txt 2> /dev/null || echo $(PROJECT_NAME)
    printf "${NO_CLR}\n"
endef

define printMessage
    printf "${2}$(MSG_PRFX) %s$(MSG_SFX)${NO_CLR}\n" ${1} 2>&1
endef

.PHONY: utils
utils: help list stats todo

.PHONY: help
help: ## to get help about the targets.
	$(call displayProjectLogo,$(OK_CLR)) 2>&1
	awk 'BEGIN {FS = ":.*?## "}; \
		/^[a-zA-Z._-]+%?:.*?## .*$$/ {sub("\\\\n", sprintf("\n%22c"," "), $$2); \
		printf "  $(STAR) $(HELP_CLR)%-28s${NO_CLR} %s\n", $$1, $$2} \
		/^##@/ { printf "\n$(INFO_CLR)%s${NO_CLR}\n", substr($$0, 5) } \
    /^##-/ { printf "  %-17s\n", substr($$0, 5) }' \
		$(MAKEFILE_LIST) | sort -u 2>&1
	printf "\n$(INFO_CLR)Useful variables:${NO_CLR}\n"
	awk 'BEGIN { FS = "[:?]=" }; \
		/^## /{x = substr($$0, 4); getline; \
		if (NF >= 2) printf "  $(PLUS) $(DISCLAIMER_CLR)%-29s${NO_CLR} %s\n", $$1, x}' \
		$(MAKEFILE_LIST) | sort -u 2>&1

.PHONY: list
list: ## to list all targets.
	awk -F':' '/^[a-z0-9][^$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /); \
		for(i in A)printf "$(LIST_CLR)%-30s${NO_CLR}\n", A[i]}' \
		$(MAKEFILE_LIST) | sort -u 2>&1

.PHONY: print-%
print-%: ## to print arbitrary variables use `print-VARNAME`
	echo "$(DISCLAIMER_CLR)$*${NO_CLR} = $($*)"

.PHONY: stats
stats: ## to output source statistics.
	$(call printMessage,"📊 Calculating source statistics",$(INFO_CLR))
	tokei --exclude=node_modules,vendor . 2>&1

.PHONY: todo
todo: $(ARTIFACTS_DIR) ## to output to-do items per file.
	$(call printMessage,"🔎️ Searching for todos",$(INFO_CLR))
	todos="$$(todoPrefix="TODO"; \
		grep \
		--color \
		--exclude-dir=./.artifacts \
		--exclude-dir=./assets \
		--exclude-dir=./vendor \
		--exclude-dir=./node_modules \
		--text \
		-inRo \
		" $${todoPrefix}:.*" . )" ; \
	if [ -n "$${todos}" ]; then \
		echo "${ITEM_CLR}$${todos}${NO_CLR}"; \
		echo "$${todos}" > "${ARTIFACTS_DIR}/TODOs.txt"; \
	fi
