get_active_tracks = ->
	accepted =
		video: true
		audio: not mp.get_property_bool("mute")
		sub: mp.get_property_bool("sub-visibility")
	active = {}
	for _, track in ipairs mp.get_property_native("track-list")
		if track["selected"] and accepted[track["type"]]
			active[#active + 1] = track
	return active

get_scale_filters = ->
	if options.scale_height > 0
		return {"scale=-1:#{options.scale_height}"}
	return {}

append_property = (out, property_name, option_name) ->
	option_name = option_name or property_name
	prop = mp.get_property(property_name)
	if prop and prop != ""
		append(out, {"--#{option_name}=#{prop}"})

-- Reads a mpv "list option" property and set the corresponding command line flags (as specified on the manual)
-- option_prefix is optional, will be set to property_name if empty
append_list_options = (out, property_name, option_prefix) ->
	option_prefix = option_prefix or property_name
	prop = mp.get_property_native(property_name)
	if prop
		for value in *prop
			append(out, {"--#{option_prefix}-append=#{value}"})

-- Get the current playback options, trying to match how the video is being played.
get_playback_options = ->
	ret = {}
	append_property(ret, "sub-ass-override")
	append_property(ret, "sub-ass-force-style")
	append_property(ret, "sub-auto")

	-- tracks added manually (eg. drag-and-drop) won't appear on sub-files, so we
	-- read them from the track-list.
	for _, track in ipairs mp.get_property_native("track-list")
		if track["type"] == "sub" and track["external"]
			append(ret, {"--sub-files-append=#{track['external-filename']}"})

	return ret

encode = (region, startTime, endTime) ->
	format = formats[options.output_format]

	path = mp.get_property("path")
	if not path
		message("No file is being played")
		return

	is_stream = not file_exists(path)

	command = {
		"mpv", path,
		"--start=" .. seconds_to_time_string(startTime, false, true),
		"--end=" .. seconds_to_time_string(endTime, false, true),
		"--ovc=#{format.videoCodec}", "--oac=#{format.audioCodec}",
		-- When loop-file=inf, the encode won't end. Set this to override.
		"--loop-file=no"
	}

	vid = -1
	aid = -1
	sid = -1
	for _, track in ipairs get_active_tracks!
		switch track["type"]
			when "video"
				vid = track['id']
			when "audio"
				aid = track['id']
			when "sub"
				sid = track['id']

	append(command, {
		"--vid=" .. (vid >= 0 and tostring(vid) or "no"),
		"--aid=" .. (aid >= 0 and tostring(aid) or "no"),
		"--sid=" .. (sid >= 0 and tostring(sid) or "no")
	})

	append(command, get_playback_options!)

	filters = {}
	append(filters, format\getPreFilters!)

	-- Even if we don't have a set region, the user might have external crops applied.
	-- Solve this by using a region that covers the entire visible screen.
	if not region or not region\is_valid!
		msg.verbose("Invalid/unset region, using fullscreen one.")
		region = make_fullscreen_region!

	append(filters, {"crop=#{region.w}:#{region.h}:#{region.x}:#{region.y}"})

	append(filters, get_scale_filters!)

	append(filters, format\getPostFilters!)

	if #filters > 0
		append(command, {
			"--vf", "lavfi=[#{table.concat(filters, ',')}]"
		})

	append(command, format\getFlags!)

	if options.target_filesize > 0 and format.acceptsBitrate
		dT = endTime - startTime
		if options.strict_filesize_constraint
			-- Calculate video bitrate, assume audio is constant.
			video_kilobits = options.target_filesize * 8
			if aid >= 0 -- compensate for audio
				video_kilobits = video_kilobits - dT * options.strict_audio_bitrate
				append(command, {
					"--oacopts-add=b=#{options.strict_audio_bitrate}k"
				})
			video_kilobits *= options.strict_bitrate_multiplier
			bitrate = math.floor(video_kilobits / dT)
			append(command, {
				"--ovcopts-add=b=#{bitrate}k",
				"--ovcopts-add=minrate=#{bitrate}k",
				"--ovcopts-add=maxrate=#{bitrate}k",
			})
		else
			-- Loosely set the video bitrate.
			bitrate = math.floor(options.target_filesize * 8 / dT)
			append(command, {
				"--ovcopts-add=b=#{bitrate}k"
			})

	-- split the user-passed settings on whitespace
	for token in string.gmatch(options.additional_flags, "[^%s]+") do
		command[#command + 1] = token
	
	if not options.strict_filesize_constraint
		for token in string.gmatch(options.non_strict_additional_flags, "[^%s]+") do
			command[#command + 1] = token

	-- Do the first pass now, as it won't require the output path. I don't think this works on streams.
	-- Also this will ignore run_detached, at least for the first pass.
	if options.twopass and format.supportsTwopass and not is_stream
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
			return
		-- set the second pass flag on the final encode command
		append(command, {
			"--ovcopts-add=flags=+pass2"
		})

	dir = ""
	if is_stream
		dir = parse_directory("~")
	else
		dir, _ = utils.split_path(path)

	if options.output_directory != ""
		dir = parse_directory(options.output_directory)
	
	formatted_filename = format_filename(startTime, endTime, format)
	out_path = utils.join_path(dir, formatted_filename)
	append(command, {"-o=#{out_path}"})

	msg.info("Encoding to", out_path)
	msg.verbose("Command line:", table.concat(command, " "))

	if options.run_detached
		message("Started encode, process was detached.")
		utils.subprocess_detached({args: command})
	else
		message("Started encode...")
		res = run_subprocess({args: command, cancellable: false})
		if res
			message("Encoded successfully! Saved to\\N#{bold(out_path)}")
		else
			message("Encode failed! Check the logs for details.")
