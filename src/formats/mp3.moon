class MP3 extends Format
    new: =>
		@displayName = "MP3 (libmp3lame)"
		@supportsTwopass = false -- uhh
		@videoCodec = ""
		@audioCodec = "libmp3lame"
		@outputExtension = "mp3"
		@acceptsBitrate = true

formats["mp3"] = MP3!
