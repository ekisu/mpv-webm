class GIF extends Format
	new: =>
		@displayName = "GIF"
		@supportsTwopass = false
		@videoCodec = "gif"
		@audioCodec = ""
		@outputExtension = "gif"
		@acceptsBitrate = false

formats["gif"] = GIF!
