# The order of the sources does matter.
LUASOURCES := src/requires.lua
LUASOURCES += src/options.lua
LUASOURCES += src/base64.lua

SOURCES += src/util.moon
SOURCES += src/video_to_screen.moon
SOURCES += src/vp8_twopass_log_patcher.moon
SOURCES += src/formats/base.moon
SOURCES += src/formats/rawvideo.moon
SOURCES += src/formats/webm.moon
SOURCES += src/formats/mp4.moon
SOURCES += src/Page.moon
SOURCES += src/EncodeWithProgress.moon
SOURCES += src/encode.moon
SOURCES += src/CropPage.moon
SOURCES += src/EncodeOptionsPage.moon
SOURCES += src/PreviewPage.moon
SOURCES += src/MainPage.moon
SOURCES += src/main.moon

MAKEFILE_DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
TMPDIR       := $(MAKEFILE_DIR)/build
JOINEDSRC    := $(TMPDIR)/webm_bundle.moon
OUTPUT       := $(JOINEDSRC:.moon=.lua)
JOINEDLUASRC := $(TMPDIR)/webm.lua
RESULTS      := $(addprefix $(TMPDIR)/, $(SOURCES:.moon=.lua))
MPVCONFIGDIR := ~/.config/mpv/

.PHONY: all clean subprocess_helper

all: $(JOINEDLUASRC)

$(OUTPUT): $(JOINEDSRC)
	@printf 'Building %s\n' $@
	@moonc -o $@ $<

$(JOINEDSRC): $(SOURCES) | $(TMPDIR)
	@printf 'Generating %s\n' $@
	@cat $^ > $@

$(JOINEDLUASRC): $(LUASOURCES) $(OUTPUT) | $(TMPDIR)
	@printf 'Joining with Lua sources into %s.\n' $@
	@cat $^ > $@

$(TMPDIR)/%.lua: %.moon
	@printf 'Building %s\n' $@
	@moonc -o $@ $< 2>/dev/null

$(TMPDIR):
	@mkdir -p $@

$(TMPDIR)/%/: | $(TMPDIR)
	@mkdir -p $@

install: $(JOINEDLUASRC)
	install -d $(MPVCONFIGDIR)/scripts/
	install -m 644 $(JOINEDLUASRC) $(MPVCONFIGDIR)/scripts/

clean:
	@rm -rf $(TMPDIR)
	$(MAKE) -C src/subprocess_helper clean TMPDIR=$(TMPDIR)

subprocess_helper:
	$(MAKE) -C src/subprocess_helper TMPDIR=$(TMPDIR)
