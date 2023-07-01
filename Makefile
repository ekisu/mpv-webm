# The order of the sources does matter.
LUASOURCES := src/requires.lua
LUASOURCES += src/options.lua
LUASOURCES += src/base64.lua

SOURCES += src/testing.moon
SOURCES += src/util.moon
SOURCES += src/video_to_screen.moon
SOURCES += src/vp8_twopass_log_patcher.moon
SOURCES += src/formats/base.moon
SOURCES += src/formats/rawvideo.moon
SOURCES += src/formats/webm.moon
SOURCES += src/formats/avc.moon
SOURCES += src/formats/av1.moon
SOURCES += src/formats/hevc.moon
SOURCES += src/formats/mp3.moon
SOURCES += src/formats/gif.moon
SOURCES += src/Page.moon
SOURCES += src/EncodeWithProgress.moon
SOURCES += src/encode.moon
SOURCES += src/CropPage.moon
SOURCES += src/EncodeOptionsPage.moon
SOURCES += src/PreviewPage.moon
SOURCES += src/MainPage.moon
SOURCES += src/main.moon

TMPDIR       := build
JOINEDSRC    := $(TMPDIR)/webm_bundle.moon
OUTPUT       := $(JOINEDSRC:.moon=.lua)
JOINEDLUASRC := $(TMPDIR)/webm.lua
CONFFILE     := $(TMPDIR)/webm.conf
RESULTS      := $(addprefix $(TMPDIR)/, $(SOURCES:.moon=.lua))
MPVCONFIGDIR := ~/.config/mpv/

.PHONY: all clean

all: $(JOINEDLUASRC) $(CONFFILE)

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

$(CONFFILE): src/options.lua
	@printf 'Generating %s\n' $@
	@lua build-webm-conf.lua > $@

install: $(JOINEDLUASRC)
	install -d $(MPVCONFIGDIR)/scripts/
	install -m 644 $(JOINEDLUASRC) $(MPVCONFIGDIR)/scripts/

clean:
	@rm -rf $(TMPDIR)
