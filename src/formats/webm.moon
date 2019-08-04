class WebmVP8 extends Format
	new: =>
		@displayName = "WebM"
		@supportsTwopass = true
		@videoCodec = "libvpx"
		@audioCodec = "libvorbis"
		@outputExtension = "webm"
		@acceptsBitrate = true

	getPreFilters: =>
		-- colormatrix filter
		colormatrixFilter =
			"bt.709": "bt709"
			"bt.2020": "bt2020"
			"smpte-240m": "smpte240m"
		ret = {}
		-- vp8 only supports bt.601, so add a conversion filter
		-- thanks anon
		-- 04/08/2019: as of now, mpv freezes sometimes when using the colormatrix
		-- filter (and seemingly other libavfilter filters), so this is disabled.
		-- colormatrix = mp.get_property_native("video-params/colormatrix")
		-- if colormatrixFilter[colormatrix]
		--	append(ret, {
		--		"lavfi-colormatrix=#{colormatrixFilter[colormatrix]}:bt601"
		--	})
		return ret

	getFlags: =>
		{
			"--ovcopts-add=threads=#{options.libvpx_threads}"
		}

formats["webm-vp8"] = WebmVP8!

class WebmVP9 extends Format
	new: =>
		@displayName = "WebM (VP9)"
		@supportsTwopass = true
		@videoCodec = "libvpx-vp9"
		@audioCodec = "libvorbis"
		@outputExtension = "webm"
		@acceptsBitrate = true

	getFlags: =>
		{
			"--ovcopts-add=threads=#{options.libvpx_threads}"
		}

formats["webm-vp9"] = WebmVP9!
