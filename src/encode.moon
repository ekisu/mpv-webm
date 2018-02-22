-- Represents a video/audio/subtitle track.
class Track
	new: (id, index, type) =>
		@id = id
		@index = index
		@type = type

-- Represents an mpv video/audio filter.
class MpvFilter
	new: (name, params={}) =>
		-- Note: You don't need to specify the lavfi- prefix to
		-- use valid lavfi filters, it's only used as a disambiguation
		-- against mpv's builtin filters. So not all compatible filters
		-- will be caught here.
		if string.sub(name,1,6)=="lavfi-" then
			@name = string.sub(name,7,string.len(name))
			@lavfiCompat = true
		else
			@name = name
			@lavfiCompat = false
		@params = params

class EncodingParameters
	new: =>
		-- {Format}
		-- The format to encode in.
		@format = nil

		-- {string}
		-- The full path to the input stream.
		@inputPath = nil

		-- {string}
		-- The output path the encoding will be written to.
		@outputPath = nil

		-- {number}
		-- The start time in milliseconds.
		@startTime = 0

		-- {number}
		-- The end time in milliseconds.
		@endTime = 0

		-- {Region}
		-- A region specifying how to crop the video. `nil`
		-- for no cropping.
		@crop = nil

		-- {Point}
		-- A point specifying how the video should be
		-- scaled. `nil` means no scaling and `-1` for
		-- either x or y means aspect ratio should be
		-- maintained.
		@scale = nil

		-- {Track}
		-- The video track to include. `nil` for no video.
		@videoTrack = nil

		-- {Track}
		-- The audio track to include. `nil` for no audio.
		@audioTrack = nil

		-- {Track}
		-- The subtitle track to include. `nil` for no
		-- subtitles.
		@subTrack = nil

		-- {number}
		-- The target bitrate in kB. `0` to disable.
		@bitrate = 0

		-- {number}
		-- The minimum allowed bitrate in kB. `0` to
		-- disable.
		@minBitrate = 0

		-- {number}
		-- The maximum allowed bitrate in kB. `0` to
		-- disable.
		@maxBitrate = 0

		-- {number}
		-- The target audio bitrate in kB. `0` to disable.
		@audioBitrate = 0

		-- {boolean}
		-- Whether or not to use two-pass encoding.
		@twopass = false

		-- {MpvFilter[]}
		-- A table of additional mpv filters that should be
		-- applied to the encoding, or attempted to.
		@mpvFilters = {}

		-- {Table}
		-- Additional (backend-specific) flags.
		@flags = {}

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
	backend = backends[options.encoder]
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
		res = backend\encodeDetached(params)
		if res
			message("Started encode, process was detached. (#{backend.name})")
		else
			message("Encode failed! Couldn't start encode. Check the logs for details.")
	else
		message("Started encode... (#{backend.name})")
		res = backend\encode(params)
		if res
			message("Encoded successfully! Saved to\\N#{bold(res)}")
		else
			message("Encode failed! Check the logs for details.")
