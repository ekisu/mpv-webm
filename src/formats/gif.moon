class GIF extends Format
	new: =>
		@displayName = "GIF"
		@supportsTwopass = false
		@videoCodec = "gif"
		@audioCodec = ""
		@outputExtension = "gif"
		@acceptsBitrate = false
		-- GIF builds its own video filter graph, so it applies the speed
		-- trim/setpts itself; encode then skips the generic video speed flags.
		@handlesSpeedInFilterGraph = true
		-- The sub filter runs after the graph retimes the video, so it needs
		-- encoder-domain subtitle speed/delay, just like other video formats.
		@rendersSubtitlesInSourceTime = false

	postCommandModifier: (command, region, times) =>
		new_command = {}

		start_ts = seconds_to_time_string(times.sourceStart, false, true)
		end_ts = seconds_to_time_string(times.sourceEnd, false, true)
		-- Escape hell...
		start_ts = start_ts\gsub(":", "\\\\:")
		end_ts = end_ts\gsub(":", "\\\\:")

		-- Need to use both trim and --start/--end
		cfilter = "[in]trim=start=#{start_ts}:end=#{end_ts}[vidtmp];"

		-- Mirror the default trim -> setpts order inside the graph.
		if times.speed != 1
			cfilter = cfilter .. "[vidtmp]setpts=(PTS-#{times.sourceStart}/TB)/#{times.speed}[vidtmp];"
			cfilter = cfilter .. "[vidtmp]setpts=PTS+#{times.sourceStart}/TB[vidtmp];"

		-- We iterate over commands in the order they are.
		-- The order is OK except for deinterlace which needs to be applied first:
		if mp.get_property("deinterlace") == "yes"
			cfilter = cfilter .. "[vidtmp]yadif=mode=1[vidtmp];"

		-- Remove vf-add commands and prepare a complex filter
		for _, v in ipairs command
			-- Other possible vf commands may be OK, but only convert fps, scale, crop, rotate and eq for now
			if v\match("^%-%-vf%-add=lavfi%-scale") or v\match("^%-%-vf%-add=lavfi%-crop") or
				   v\match("^%-%-vf%-add=fps") or v\match("^%-%-vf%-add=lavfi%-eq")
				n = v\gsub("^%-%-vf%-add=", "")\gsub("^lavfi%-", "")
				cfilter = cfilter .. "[vidtmp]#{n}[vidtmp];"
			else if v\match("^%-%-video%-rotate=90")
				cfilter = cfilter .. "[vidtmp]transpose=1[vidtmp];"
			else if v\match("^%-%-video%-rotate=270")
				cfilter = cfilter .. "[vidtmp]transpose=2[vidtmp];"
			else if v\match("^%-%-video%-rotate=180")
				cfilter = cfilter .. "[vidtmp]transpose=1[vidtmp];[vidtmp]transpose=1[vidtmp];"
			else if v\match("^%-%-deinterlace=")
				-- Drop deinterlace option, yadif filter applied added above instead
				continue
			else
				-- Copy rest of the commands as they are (some might break palette use)
				append(new_command, {v})
				continue

		-- Finish the video filter graph before rendering subtitles. This matches
		-- normal mpv playback, where subtitles are rendered over the cropped
		-- and scaled video rather than being cropped with the source frame.
		cfilter = cfilter .. "[vidtmp]null[out]"
		append(new_command, { "--vf-add=lavfi=[#{cfilter}]", "--vf-add=sub" })

		-- Generate the palette after subtitles have been rendered so subtitle
		-- colors are represented in the GIF palette.
		palette_filter = "[in]split[topal][vidf];"
		palette_filter = palette_filter .. "[topal]palettegen[pal];"
		palette_filter = palette_filter .. "[vidf][pal]paletteuse=diff_mode=rectangle"
		if options.gif_dither != 6
			palette_filter = palette_filter .. ":dither=bayer:bayer_scale=#{options.gif_dither}"
		palette_filter = palette_filter .. "[out]"
		append(new_command, { "--vf-add=lavfi=[#{palette_filter}]" })

		return new_command

formats["gif"] = GIF!
