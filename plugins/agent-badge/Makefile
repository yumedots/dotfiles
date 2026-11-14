OUT ?= .

all: $(OUT)/Entry.qml

$(OUT)/Entry.qml: Entry.qml
	mkdir -p $(OUT)
	cp Entry.qml $@

clean:
	rm -f $(OUT)/Entry.qml

.PHONY: all clean
