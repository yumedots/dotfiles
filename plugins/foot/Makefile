OUT ?= .

all: $(OUT)/theme.ini

$(OUT)/theme.ini: theme.ini
	mkdir -p $(OUT)
	cp theme.ini $@

clean:
	rm -f $(OUT)/theme.ini

.PHONY: all clean
