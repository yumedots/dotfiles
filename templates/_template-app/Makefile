OUT ?= .

all: $(OUT)/app.conf

$(OUT)/app.conf: app.conf
	mkdir -p $(OUT)
	cp app.conf $@

clean:
	rm -f $(OUT)/app.conf

.PHONY: all clean
