class MP4 extends Format
	new: =>
		@displayName = "MP4 (h264/AAC)"
		@supportsTwopass = true
		@videoCodec = "libx264"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

formats["mp4"] = MP4!
