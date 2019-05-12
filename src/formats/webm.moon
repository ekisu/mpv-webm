class WebmVP8 extends Format
	new: =>
		@displayName = "WebM"
		@supportsTwopass = true
		@videoCodec = "libvpx"
		@audioCodec = "libvorbis"
		@outputExtension = "webm"
		@acceptsBitrate = true

	getPreFilters: (backend) =>
		-- colormatrix filter
		colormatrixFilter =
			"bt.709": "bt709"
			"bt.2020": "bt2020"
			"smpte-240m": "smpte240m"
		ret = {}
		-- vp8 only supports bt.601, so add a conversion filter
		-- thanks anon
		colormatrix = mp.get_property_native("video-params/colormatrix")
		if colormatrixFilter[colormatrix]
			append(ret, {
				MpvFilter("lavfi-colormatrix",
					{ "src": colormatrixFilter[colormatrix],
					  "dst": "bt601" })
			})
		return ret

	getFlags: (backend) =>
		switch backend.name
			when "mpv"
				return {"--ovcopts-add=threads=#{options.libvpx_threads}"}
			when "ffmpeg"
				return {"-threads", tostring(options.libvpx_threads)}

formats["webm-vp8"] = WebmVP8!

class WebmVP9 extends Format
	new: =>
		@displayName = "WebM (VP9)"
		@supportsTwopass = true
		@videoCodec = "libvpx-vp9"
		@audioCodec = "libvorbis"
		@outputExtension = "webm"
		@acceptsBitrate = true

	getFlags: (backend) =>
		switch backend.name
			when "mpv"
				return {"--ovcopts-add=threads=#{options.libvpx_threads}"}
			when "ffmpeg"
				return {"-threads", options.libvpx_threads}

formats["webm-vp9"] = WebmVP9!
