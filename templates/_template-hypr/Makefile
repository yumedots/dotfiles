OUT ?= $(or $(XDG_STATE_HOME),$(HOME)/.local/state)/yudae/build/_template-hypr

CXX ?= g++
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wall -Wno-unused-variable
CXXFLAGS += $(shell pkg-config --cflags hyprland)
LDLIBS += $(shell pkg-config --libs hyprland)

all: $(OUT)/template-hypr.so

$(OUT)/template-hypr.so: src/main.cpp
	mkdir -p $(OUT)
	$(CXX) $(CXXFLAGS) src/main.cpp -o $@ $(LDLIBS)

clean:
	rm -f $(OUT)/template-hypr.so

.PHONY: all clean
