class FfmpegBackend extends Backend
	new: =>
		@name = "ffmpeg"

	-- Turn `MpvFilter`s into command line options.
	solveFilters: (filters) =>
		solved = {}
		for filter in *filters
			if not filter.lavfiCompat
				continue
			str = filter.name .. "="
			ordered_params = {}
			highest_n = 0
			for k, v in pairs filter.params
				-- @n keys dictate the order of keyless params. Sort them here.
				param_n = tonumber(string.match(k, "^@(%d+)$"))
				if param_n ~= nil
					ordered_params[param_n] = v
					if param_n > highest_n
						highest_n = param_n
				else
					str ..= "#{k}=#{v}:"
			for i = 0, highest_n
				if ordered_params[i] ~= nil
					str ..= "#{ordered_params[i]}:"
			solved[#solved+1] = string.sub(str, 0, string.len(str) - 1)
		return solved

	buildCommand: (params) =>
		format = params.format

		-- Build the base command.
		command = {
			get_backend_location!,
			"-y",
			"-ss", seconds_to_time_string(params.startTime, false, true),
			"-i", params.inputPath,
			"-t", tostring(params.endTime - params.startTime)
		}

		-- Append our track mappings.
		if params.videoTrack ~= nil and params.videoTrack.index ~= nil
			append(command, {
				"-map", "0:" .. tostring(params.videoTrack.index)
			})
		if params.audioTrack ~= nil and params.audioTrack.index ~= nil
			append(command, {
				"-map", "0:" .. tostring(params.audioTrack.index)
			})
		if params.subTrack ~= nil and params.subTrack.index ~= nil
			append(command, {
				"-map", "0:" .. tostring(params.subTrack.index)
			})

		-- Append our video/audio codecs.
		append(command, {
			"-c:v", "#{format.videoCodec}", "-c:a", "#{format.audioCodec}"
		})

		-- Append filters: Prefilters from the format, raw filters from the parameters, cropping
		-- and scaling filters, and postfilters from the format.
		-- Begin by solving them from our parameters.
		filters = {}
		append(filters, self\solveFilters(format\getPreFilters self))
		append(filters, self\solveFilters(params.mpvFilters))
		if params.crop
			filters[#filters+1] = "crop=#{params.crop.w}:#{params.crop.h}:#{params.crop.x}:#{params.crop.y}"
		if params.scale
			filters[#filters+1] = "scale=#{params.scale.x}:#{params.scale.y}"
		append(filters, self\solveFilters(format\getPostFilters self))
		-- Then append them to the command.
		append(command, {
			"-vf", table.concat(filters, ",")
		})

		-- Append any extra flags the format wants.
		append(command, format\getFlags self)

		-- Append bitrate options.
		if format.acceptsBitrate
			if params.audioBitrate ~= 0
				append(command, {"-b:a", "#{params.audioBitrate}K"})
			if params.bitrate ~= 0
				append(command, {"-b:v", "#{params.bitrate}K"})
			if params.minBitrate ~= 0
				append(command, {"-minrate", "#{params.minBitrate}K"})
			if params.maxBitrate ~= 0
				append(command, {"-maxrate", "#{params.maxBitrate}K"})

		-- Append user-passed flags.
		for flag in *params.flags
			command[#command+1] = flag

		-- If two-pass is go, do the first pass now with the current command. Note: This
		-- ignores the user option to run the encoding process detached (for the first pass).
		if params.twopass and format.supportsTwopass
			-- copy the commandline
			first_pass_cmdline = [arg for arg in *command]
			append(first_pass_cmdline, {
				"-pass", "1",
				"-f", format.outputExtension,
				get_null_path!
			})
			message("Starting first pass...")
			msg.verbose("First-pass command line: ", table.concat(first_pass_cmdline, " "))
			res = run_subprocess({args: first_pass_cmdline, cancellable: false})
			if not res
				message("First pass failed! Check the logs for details.")
				return nil
			-- set the second pass flag on the final encode command
			append(command, {
				"-pass", "2"
			})

		-- Append the output path. It's assumed elsewhere that this parameter IS the output
		-- path. Not wise to modify it here!
		append(command, {params.outputPath})

		return command

backends["ffmpeg"] = FfmpegBackend!
