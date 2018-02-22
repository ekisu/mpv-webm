class MpvBackend extends Backend
	new: =>
		@name = "mpv"

	appendProperty: (out, property_name, option_name) =>
		option_name = option_name or property_name
		prop = mp.get_property(property_name)
		if prop and prop != ""
			append(out, {"--#{option_name}=#{prop}"})

	getPlaybackOptions: =>
		ret = {}
		self\appendProperty(ret, "sub-ass-override")
		self\appendProperty(ret, "sub-ass-force-style")
		self\appendProperty(ret, "sub-auto")

		-- tracks added manually (eg. drag-and-drop) won't appear on sub-files, so we
		-- read them from the track-list.
		for _, track in ipairs mp.get_property_native("track-list")
			if track["type"] == "sub" and track["external"]
				append(ret, {"--sub-files-append=#{track['external-filename']}"})

		return ret

	-- Turn `MpvFilter`s into command line options.
	solveFilters: (filters) =>
		solved = {}
		for filter in *filters
			str = filter.lavfiCompat and "lavfi-" or ""
			str ..= filter.name .. "="
			for k, v in pairs filter.params
				if tonumber(k) == nil
					str ..= "#{k}=%#{string.len(v)}%#{v}:"
				else
					str ..= "#{v}:"
			solved[#solved+1] = string.sub(str, 0, string.len(str) - 1)
		return solved

	buildCommand: (params) =>
		format = params.format

		-- Build the base command.
		command = {
			get_backend_location!, params.inputPath,
			"--start=" .. seconds_to_time_string(params.startTime, false, true),
			"--end=" .. seconds_to_time_string(params.endTime, false, true),
			"--ovc=#{format.videoCodec}", "--oac=#{format.audioCodec}",
			-- When loop-file=inf, the encode won't end. Set this to override.
			"--loop-file=no"
		}

		-- Append video/audio/sub track options.
		append(command, {
			"--vid=" .. (params.videoTrack ~= nil and tostring(params.videoTrack.id) or "no"),
			"--aid=" .. (params.audioTrack ~= nil and tostring(params.audioTrack.id) or "no"),
			"--sid=" .. (params.subTrackId ~= nil and tostring(params.subTrack.id) or "no")
		})

		-- Append mpv exclusive options based on playback to have the encoding match it
		-- as much as possible.
		append(command, self\getPlaybackOptions!)

		-- Append filters: Prefilters from the format, raw filters from the parameters, cropping
		-- and scaling filters, and postfilters from the format.
		-- Begin by solving them from our parameters.
		filters = {}
		append(filters, self\solveFilters(format\getPreFilters self))
		append(filters, self\solveFilters(params.mpvFilters))
		if params.crop
			filters[#filters+1] = "lavfi-crop=#{params.crop.w}:#{params.crop.h}:#{params.crop.x}:#{params.crop.y}"
		if params.scale
			filters[#filters+1] = "lavfi-scale=#{params.scale.x}:#{params.scale.y}"
		append(filters, self\solveFilters(format\getPostFilters self))
		-- Then append them to the command.
		for f in *filters
			command[#command+1] = "--vf-add=#{f}"

		-- Append any extra flags the format wants.
		append(command, format\getFlags self)

		-- Append bitrate options.
		if format.acceptsBitrate
			if params.audioBitrate ~= 0
				command[#command+1] = "--oacopts-add=b=#{params.audioBitrate}k"
			if params.bitrate ~= 0
				command[#command+1] = "--ovcopts-add=b=#{params.bitrate}k"
			if params.minBitrate ~= 0
				command[#command+1] = "--ovcopts-add=minrate=#{params.bitrate}k"
			if params.maxBitrate ~= 0
				command[#command+1] = "--ovcopts-add=maxrate=#{params.bitrate}k"

		-- Append user-passed flags.
		for flag in *params.flags
			command[#command+1] = flag

		-- If two-pass is go, do the first pass now with the current command. Note: This
		-- ignores the user option to run the encoding process detached (for the first pass).
		-- (Kind of shit to do this in a method called "buildCommand" but eh)
		if params.twopass and format.supportsTwopass
			-- copy the commandline
			first_pass_cmdline = [arg for arg in *command]
			append(first_pass_cmdline, {
				"--ovcopts-add=flags=+pass1",
				"-of=#{format.outputExtension}",
				"-o=#{get_null_path!}"
			})
			message("Starting first pass...")
			msg.verbose("First-pass command line: ", table.concat(first_pass_cmdline, " "))
			res = run_subprocess({args: first_pass_cmdline, cancellable: false})
			if not res
				message("First pass failed! Check the logs for details.")
				return nil
			-- set the second pass flag on the final encode command
			append(command, {
				"--ovcopts-add=flags=+pass2"
			})

		-- Append the output path. It's assumed elsewhere that this parameter IS the output
		-- path. Not wise to modify it here!
		append(command, {"-o=#{params.outputPath}"})

		return command

backends["mpv"] = MpvBackend!
