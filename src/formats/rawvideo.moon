class RawVideo extends Format
	new: =>
		@displayName = "Raw"
		@supportsTwopass = false
		@videoCodec = "rawvideo"
		@audioCodec = "pcm_s16le"
		@outputExtension = "avi"
		@acceptsBitrate = false

	getColorspace: =>
		-- This is very similar to the one we have in WebmVP8. Maybe we
		-- could find a way to unify them?
		csp = mp.get_property("colormatrix")
		switch csp
			when "bt.601"
				return "bt601"
			when "bt.709"
				return "bt709"
			when "bt.2020"
				return "bt2020"
			when "smpte-240m"
				return "smpte240m"
			else
				-- Probably using the OSD right now isn't very useful, as it will probably
				-- be used to print the "Encoding..." message really soon.
				msg.info("Warning, unknown colorspace #{csp} detected, using bt.601.")
				return "bt601"

	getPostFilters: =>
		{"format=yuv444p16", "lavfi-scale=in_color_matrix=" .. self\getColorspace!, "format=bgr24"}

formats["raw"] = RawVideo!
