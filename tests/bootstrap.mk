SDK_VERSION = 37
EMPTY_FLAGS := $(file <empty-flags.txt)

probe.txt:
	printf '%s\n' '$(SDK_VERSION)$(EMPTY_FLAGS)' > $@
