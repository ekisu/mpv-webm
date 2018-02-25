get_active_tracks = ->
	accepted =
		video: true
		audio: not mp.get_property_bool("mute")
		sub: mp.get_property_bool("sub-visibility")
	active = {}
	for _, track in ipairs mp.get_property_native("track-list")
		if track["selected"] and accepted[track["type"]]
			active[#active + 1] = Track(track["id"], track["ff-index"], track["type"])
	return active

get_current_filters = ->
	current_filters = mp.get_property_native("vf")
	filters = {}
	msg.verbose("apply_current_filters: got #{#current_filters} currently applied.")
	for filter in *current_filters
		msg.verbose("apply_current_filters: filter name: #{filter['name']}")
		-- This might seem like a redundant check (if not filter["enabled"] would achieve the same result),
		-- but the enabled field isn't guaranteed to exist... and if it's nil, "not filter['enabled']"
		-- would achieve a different outcome.
		if filter.enabled == false
			continue
		-- We apply our own crop filter.
		if filter.name == "crop"
			continue
		filters[#filters+1] = MpvFilter(filter.name, filter.params)
	return filters

encode = (region, startTime, endTime) ->
	backend = backends[options.backend]
	format = formats[options.output_format]

	params = EncodingParameters!
	params.format = format
	params.startTime = startTime
	params.endTime = endTime

	params.inputPath = mp.get_property("path")
	if not params.inputPath
		message("No file is being played")
		return

	for _, track in ipairs get_active_tracks!
		switch track["type"]
			when "video"
				params.videoTrack = track
			when "audio"
				params.audioTrack = track
			when "sub"
				params.subTrack = track

	if options.scale_height > 0
		params.scale = Point(-1, options.scale_height)

	if options.apply_current_filters
		params.mpvFilters = get_current_filters!
	
	-- Even if we don't have a set region, the user might have external crops applied.
	-- Solve this by using a region that covers the entire visible screen.
	if not region or not region\is_valid!
		msg.verbose("Invalid/unset region, using fullscreen one.")
		params.crop = make_fullscreen_region!
	else
		params.crop = region

	if options.target_filesize > 0
		dT = endTime - startTime
		if options.strict_filesize_constraint
			-- Calculate video bitrate, assume audio is constant.
			video_kilobits = options.target_filesize * 8
			if params.audioTrack ~= nil -- compensate for audio
				video_kilobits = video_kilobits - dT * options.strict_audio_bitrate
				params.audioBitrate = options.strict_audio_bitrate
			video_kilobits *= options.strict_bitrate_multiplier
			bitrate = math.floor(video_kilobits / dT)
			params.bitrate = bitrate
			params.minBitrate = bitrate
			params.maxBitrate = bitrate
		else
			-- Loosely set the video bitrate.
			bitrate = math.floor(options.target_filesize * 8 / dT)
			params.bitrate = bitrate

	-- split the user-passed settings on whitespace
	for token in string.gmatch(options.additional_flags, "[^%s]+") do
		params.flags[#params.flags + 1] = token
	
	if not options.strict_filesize_constraint
		for token in string.gmatch(options.non_strict_additional_flags, "[^%s]+") do
			params.flags[#params.flags + 1] = token

	is_stream = not file_exists(params.inputPath)

	params.twopass = options.twopass and not is_stream

	dir = ""
	if options.output_directory != ""
		dir = options.output_directory
	elseif is_stream
		dir = parse_directory("~")
	else
		dir, _ = utils.split_path(params.inputPath)
	
	formatted_filename = format_filename(startTime, endTime, format)
	out_path = utils.join_path(dir, formatted_filename)

	params.outputPath = out_path

	if options.run_detached
		res = backend\encode(params, true)
		if res
			message("Started encode, process was detached. (#{backend.name})")
		else
			message("Encode failed! Couldn't start encode. Check the logs for details.")
	else
		message("Started encode... (#{backend.name})")
		res = backend\encode(params, false)
		if res
			message("Encoded successfully! Saved to\\N#{bold(params.outputPath)}")
		else
			message("Encode failed! Check the logs for details.")
