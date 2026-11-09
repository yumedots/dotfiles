OUT ?= .

ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b
DEPS     = pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon
TARGET   = $(OUT)/borders-plus-plus.so

all: $(TARGET)

$(TARGET): main.cpp borderDeco.cpp borderDeco.hpp globals.hpp
	mkdir -p $(OUT)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) main.cpp borderDeco.cpp -o $(TARGET) `pkg-config --cflags $(DEPS)`

clean:
	rm -f $(TARGET)

.PHONY: all clean
