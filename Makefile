# The order of the sources does matter.
SOURCES := src/requires.moon
SOURCES += src/options.moon
SOURCES += src/util.moon
SOURCES += src/video_to_screen.moon
SOURCES += src/encode.moon
SOURCES += src/Page.moon
SOURCES += src/CropPage.moon
SOURCES += src/EncodeOptionsPage.moon
SOURCES += src/MainPage.moon
SOURCES += src/main.moon

TMPDIR    := build
JOINEDSRC := $(TMPDIR)/webm.moon
OUTPUT    := $(JOINEDSRC:.moon=.lua)
RESULTS   := $(addprefix $(TMPDIR)/, $(SOURCES:.moon=.lua))

.PHONY: all clean

all: $(OUTPUT)

$(OUTPUT): $(JOINEDSRC)
	@printf 'Building %s\n' $@
	@moonc -o $@ $< 2>/dev/null

$(JOINEDSRC): $(SOURCES) | $(TMPDIR)
	@printf 'Generating %s\n' $@
	@cat $^ > $@

$(TMPDIR)/%.lua: %.moon
	@printf 'Building %s\n' $@
	@moonc -o $@ $< 2>/dev/null

$(TMPDIR):
	@mkdir -p $@

$(TMPDIR)/%/: | $(TMPDIR)
	@mkdir -p $@

clean:
	@rm -rf $(TMPDIR)