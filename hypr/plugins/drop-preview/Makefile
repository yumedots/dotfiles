ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wall -Wno-non-template-friend
DEPS     = pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon
SRC      = src/main.cpp src/Prediction.cpp src/Config.cpp src/Input.cpp
HDR      = src/Prediction.hpp src/Config.hpp src/Input.hpp

all: drop-preview.so

drop-preview.so: $(SRC) $(HDR)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $(SRC) -o $@ `pkg-config --cflags $(DEPS)`

clean:
	rm -f drop-preview.so

.PHONY: all clean
