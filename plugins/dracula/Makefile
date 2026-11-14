OUT ?= .

all: $(OUT)/theme.toml

$(OUT)/theme.toml: theme.toml
	mkdir -p $(OUT)
	cp theme.toml $@

clean:
	rm -f $(OUT)/theme.toml

.PHONY: all clean
