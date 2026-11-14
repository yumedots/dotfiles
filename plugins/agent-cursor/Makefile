OUT ?= .

CXX ?= g++
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wall -Wno-unused-variable
CXXFLAGS += $(shell pkg-config --cflags hyprland)
LDLIBS += $(shell pkg-config --libs hyprland)

TARGET = $(OUT)/agent-cursor.bin

all: $(TARGET)

# The binary is built under a temporary name and renamed into place. A rewrite in
# place keeps the same inode, and a compositor that already loaded the old
# binary would keep serving the old code from its loader cache.
$(TARGET): main.cpp
	mkdir -p $(OUT)
	$(CXX) $(CXXFLAGS) main.cpp -o $(TARGET).new $(LDLIBS)
	mv -f $(TARGET).new $(TARGET)

clean:
	rm -f $(TARGET) $(TARGET).new

.PHONY: all clean
