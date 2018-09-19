# The order of the sources does matter.
LUASOURCES := src/requires.lua
LUASOURCES += src/options.lua

SOURCES += src/util.moon
SOURCES += src/video_to_screen.moon
SOURCES += src/formats/base.moon
SOURCES += src/formats/rawvideo.moon
SOURCES += src/formats/webm.moon
SOURCES += src/formats/mp4.moon
SOURCES += src/encode.moon
SOURCES += src/Page.moon
SOURCES += src/CropPage.moon
SOURCES += src/EncodeOptionsPage.moon
SOURCES += src/PreviewPage.moon
SOURCES += src/MainPage.moon
SOURCES += src/main.moon
# SOURCES += src/output_encode_progress.moon

TMPDIR       := build
JOINEDSRC    := $(TMPDIR)/webm_bundle.moon
OUTPUT       := $(JOINEDSRC:.moon=.lua)
JOINEDLUASRC := $(TMPDIR)/webm.lua
RESULTS      := $(addprefix $(TMPDIR)/, $(SOURCES:.moon=.lua))
MPVCONFIGDIR := ~/.config/mpv/

.PHONY: all clean

all: $(JOINEDLUASRC)

$(OUTPUT): $(JOINEDSRC)
	@printf 'Building %s\n' $@
	@moonc -o $@ $< 2>/dev/null

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

install: $(OUTPUT)
	install -d $(MPVCONFIGDIR)/scripts/
	install -m 644 $(JOINEDLUASRC) $(MPVCONFIGDIR)/scripts/

clean:
	@rm -rf $(TMPDIR)
