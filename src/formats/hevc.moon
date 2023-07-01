class HEVC extends Format
	new: =>
		@displayName = "HEVC"
		@supportsTwopass = true
		@videoCodec = "libx265"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	getFlags: =>
		{
			"--ovcopts-add=threads=#{options.threads}"
		}

formats["hevc"] = HEVC!
