get_active_tracks = ->
	accepted =
		video: true
		audio: not mp.get_property_bool("mute")
		sub: mp.get_property_bool("sub-visibility")
	active = 
		video: {}
		audio: {}
		sub: {}
	for _, track in ipairs mp.get_property_native("track-list")
		if track["selected"] and accepted[track["type"]]
			count = #active[track["type"]]
			active[track["type"]][count + 1] = track
	return active

append_track = (out, track) ->
	external_flag =
		"audio": "audio-file"
		"sub": "sub-file"
	internal_flag =
		"video": "vid"
		"audio": "aid"
		"sub": "sid"
	
	-- The external tracks rely on the behavior that, when using
	-- audio-file/sub-file only once, the track is selected by default.
	-- Also, for some reason, ytdl-hook produces external tracks with absurdly long
	-- filenames; this breaks our command line. Try to keep it sane, under 2048 characters.
	if track['external'] and string.len(track['external-filename']) <= 2048
		append(out, {
			"--#{external_flag[track['type']]}=#{track['external-filename']}"
		})
	else
		append(out, {
			"--#{internal_flag[track['type']]}=#{track['id']}"
		})

append_audio_tracks = (out, tracks) ->
	-- Some additional logic is needed for audio tracks because it seems
	-- multiple active audio tracks are a thing? We probably only can reliably
	-- use internal tracks for this so, well, we keep track of them and see if
	-- more than one is active.
	internal_tracks = {}

	for track in *tracks
		if track['external']
			-- For external tracks, just do the same thing.
			append_track(out, track)
		else
			append(internal_tracks, { track })

	if #internal_tracks > 1
		-- We have multiple audio tracks, so we use a lavfi-complex
		-- filter to mix them.
		filter_string = ""
		for track in *internal_tracks
			filter_string = filter_string .. "[aid#{track['id']}]"
		filter_string = filter_string .. "amix[ao]"
		append(out, {
			"--lavfi-complex=#{filter_string}"
		})
	else if #internal_tracks == 1
		append_track(out, internal_tracks[1])

get_scale_filters = ->
	if options.scale_height > 0
		return {"lavfi-scale=-2:#{options.scale_height}"}
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
	append_property(ret, "sub-delay")
	append_property(ret, "video-rotate")
	append_property(ret, "ytdl-format")

	return ret

get_speed_flags = ->
	ret = {}
	speed = mp.get_property_native("speed")
	if speed != 1
		append(ret, {
			"--vf-add=setpts=PTS/#{speed}",
			"--af-add=atempo=#{speed}",
			"--sub-speed=1/#{speed}"
		})
	return ret

get_metadata_flags = ->
	title = mp.get_property("filename/no-ext")
	return {"--oset-metadata=title=%#{string.len(title)}%#{title}"}

apply_current_filters = (filters) ->
	vf = mp.get_property_native("vf")
	msg.verbose("apply_current_filters: got #{#vf} currently applied.")
	for filter in *vf
		msg.verbose("apply_current_filters: filter name: #{filter['name']}")
		-- This might seem like a redundant check (if not filter["enabled"] would achieve the same result),
		-- but the enabled field isn't guaranteed to exist... and if it's nil, "not filter['enabled']"
		-- would achieve a different outcome.
		if filter["enabled"] == false
			continue
		str = filter["name"]
		params = filter["params"] or {}
		for k, v in pairs params
			str = str .. ":#{k}=%#{string.len(v)}%#{v}"
		append(filters, {str})

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

	active_tracks = get_active_tracks!
	for track_type, tracks in pairs active_tracks
		if track_type == "audio"
			append_audio_tracks(command, tracks)
		else
			for track in *tracks
				append_track(command, track)
	
	for track_type, tracks in pairs active_tracks
		if #tracks > 0
			continue
		switch track_type
			when "video"
				append(command, {"--vid=no"})
			when "audio"
				append(command, {"--aid=no"})
			when "sub"
				append(command, {"--sid=no"})

	append(command, get_playback_options!)

	filters = {}
	append(filters, format\getPreFilters!)

	if options.apply_current_filters
		apply_current_filters(filters)

	if region and region\is_valid!
		append(filters, {"lavfi-crop=#{region.w}:#{region.h}:#{region.x}:#{region.y}"})

	append(filters, get_scale_filters!)

	append(filters, format\getPostFilters!)

	for f in *filters
		append(command, {
			"--vf-add=#{f}"
		})

	append(command, get_speed_flags!)

	append(command, format\getFlags!)

	if options.write_filename_on_metadata
		append(command, get_metadata_flags!)

	if options.target_filesize > 0 and format.acceptsBitrate
		dT = endTime - startTime
		if options.strict_filesize_constraint
			-- Calculate video bitrate, assume audio is constant.
			video_kilobits = options.target_filesize * 8
			if #active_tracks["audio"] > 0 -- compensate for audio
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
	elseif options.target_filesize <= 0 and format.acceptsBitrate
		-- set video bitrate to 0. This might enable constant quality, or some
		-- other encoding modes, depending on the codec.
		append(command, {
			"--ovcopts-add=b=0"
		})

	-- split the user-passed settings on whitespace
	for token in string.gmatch(options.additional_flags, "[^%s]+") do
		command[#command + 1] = token

	if not options.strict_filesize_constraint
		for token in string.gmatch(options.non_strict_additional_flags, "[^%s]+") do
			command[#command + 1] = token
		
		-- Also add CRF here, as it used to be a part of the non-strict flags.
		-- This might change in the future, I don't know.
		if options.crf >= 0
			append(command, {
				"--ovcopts-add=crf=#{options.crf}"
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

	-- Do the first pass now, as it won't require the output path. I don't think this works on streams.
	-- Also this will ignore run_detached, at least for the first pass.
	if options.twopass and format.supportsTwopass and not is_stream
		-- copy the commandline
		first_pass_cmdline = [arg for arg in *command]
		append(first_pass_cmdline, {
			"--ovcopts-add=flags=+pass1"
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

		if format.videoCodec == "libvpx"
			-- We need to patch the pass log file before running the second pass.
			msg.verbose("Patching libvpx pass log file...")
			vp8_patch_logfile(get_pass_logfile_path(out_path), endTime - startTime)

	msg.info("Encoding to", out_path)
	msg.verbose("Command line:", table.concat(command, " "))

	if options.run_detached
		message("Started encode, process was detached.")
		utils.subprocess_detached({args: command})
	else
		res = false
		if not should_display_progress!
			message("Started encode...")
			res = run_subprocess({args: command, cancellable: false})
		else
			ewp = EncodeWithProgress(startTime, endTime)
			res = ewp\startEncode(command)
		if res
			message("Encoded successfully! Saved to\\N#{bold(out_path)}")
		else
			message("Encode failed! Check the logs for details.")
		
		-- Clean up pass log file.
		os.remove(get_pass_logfile_path(out_path))
