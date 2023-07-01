class AV1 extends Format
	new: =>
		@displayName = "AV1"
		@supportsTwopass = true
		@videoCodec = "libaom-av1"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	getFlags: =>
		{
			"--ovcopts-add=threads=#{options.threads}"
		}

formats["av1"] = AV1!
