OUT ?= .

all: $(OUT)/provider.txt

$(OUT)/provider.txt: provider.txt
	mkdir -p $(OUT)
	cp provider.txt $@

clean:
	rm -f $(OUT)/provider.txt

.PHONY: all clean
