CXX ?= g++
CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wall -Wno-unused-variable
CXXFLAGS += $(shell pkg-config --cflags hyprland)
LDLIBS += $(shell pkg-config --libs hyprland)

all: agent-cursor.bin

# The binary is built under a temporary name and renamed into place. A rewrite in
# place keeps the same inode, and a compositor that already loaded the old
# binary would keep serving the old code from its loader cache.
agent-cursor.bin: main.cpp
	$(CXX) $(CXXFLAGS) main.cpp -o agent-cursor.bin.new $(LDLIBS)
	mv -f agent-cursor.bin.new agent-cursor.bin

clean:
	rm -f agent-cursor.bin agent-cursor.bin.new agent-cursor.so

.PHONY: all clean
