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
		-- The sub filter runs before the graph retimes the video, so it needs
		-- source-domain subtitle speed/delay rather than encoder-domain values.
		@rendersSubtitlesInSourceTime = true

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

		-- complete the complex filter with split->palettegen->paletteuse
		cfilter = cfilter .. "[vidtmp]split[topal][vidf];"
		cfilter = cfilter .. "[topal]palettegen[pal];"

		cfilter = cfilter .. "[vidf][pal]paletteuse=diff_mode=rectangle"
		if options.gif_dither != 6
			cfilter = cfilter .. ":dither=bayer:bayer_scale=#{options.gif_dither}"
		cfilter = cfilter .. "[out]"

		-- Render subtitles before palette generation. lavfi-complex runs before
		-- mpv's video filters, so its palette cannot include subtitle colors.
		append(new_command, { "--vf-add=sub", "--vf-add=lavfi=[#{cfilter}]" })

		return new_command

formats["gif"] = GIF!
