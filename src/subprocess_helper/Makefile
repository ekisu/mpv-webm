# We inherit some variables from the Makefile of the root.
CXX = g++
CXXFLAGS = -Wall -Werror -std=c++17 -mconsole -static

TMPDIR ?= .

SOURCES := command_line.cpp
SOURCES += mpv_ipc.cpp
SOURCES += process.cpp
SOURCES += main.cpp

OUTPUT := $(TMPDIR)/webm_subprocess_helper.exe

.PHONY: all clean

all: $(OUTPUT)

clean:
	rm $(OUTPUT)

$(TMPDIR):
	@mkdir -p $@

$(OUTPUT): $(SOURCES) | $(TMPDIR)
	@printf 'Building %s\n' $@
	$(CXX) $(CXXFLAGS) $(SOURCES) -o $(OUTPUT)
