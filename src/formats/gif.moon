class GIF extends Format
	new: =>
		@displayName = "GIF"
		@supportsTwopass = false
		@videoCodec = "gif"
		@audioCodec = ""
		@outputExtension = "gif"
		@acceptsBitrate = false

	postCommandModifier: (command, region, startTime, endTime) =>
		new_command = {}

		start_ts = seconds_to_time_string(startTime, false, true)
		end_ts = seconds_to_time_string(endTime, false, true)
		-- Escape hell...
		start_ts = start_ts\gsub(":", "\\\\:")
		end_ts = end_ts\gsub(":", "\\\\:")

		-- Need to use both trim and --start/--end
		cfilter = "[vid1]trim=start=#{start_ts}:end=#{end_ts}[vidtmp];"

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
		cfilter = cfilter .. "[vo]"

		append(new_command, { "--lavfi-complex=#{cfilter}" })

		return new_command

formats["gif"] = GIF!
