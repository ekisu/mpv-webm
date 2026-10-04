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

filter_tracks_supported_by_format = (active_tracks, format) ->
	has_video_codec = format.videoCodec != ""
	has_audio_codec = format.audioCodec != ""
	
	supported =
		video: has_video_codec and active_tracks["video"] or {}
		audio: has_audio_codec and active_tracks["audio"] or {}
		sub: has_video_codec and active_tracks["sub"] or {}
	
	return supported

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
	filters = {}
	if options.force_square_pixels
		append(filters, {"lavfi-scale=iw*sar:ih"})
	if options.scale_height > 0
		append(filters, {"lavfi-scale=-2:#{options.scale_height}"})
	return filters

get_fps_filters = ->
	if options.fps > 0
		return {"fps=#{options.fps}"}
	return {}

get_contrast_brightness_and_saturation_filters = ->
	mpv_brightness = mp.get_property_number("brightness", 0)
	mpv_contrast = mp.get_property_number("contrast", 0)
	mpv_saturation = mp.get_property_number("saturation", 0)

	if mpv_brightness == 0 and mpv_contrast == 0 and mpv_saturation == 0
		-- Default values, no need to change anything.
		return {}

	-- We have to map mpv's contrast/brightness/saturation values to the ones used by the eq filter.
	-- From what I've gathered from looking at ffmpeg's source, the contrast value is used to multiply the luma
	-- channel, while the saturation one multiplies both chroma channels. On mpv, it seems that contrast multiplies
	-- both luma and chroma (?); but I don't really know a lot about how things work internally. This might cause some
	-- weird interactions, but for now I guess it's fine.
	eq_saturation = (mpv_saturation + 100) / 100.0
	eq_contrast = (mpv_contrast + 100) / 100.0

	-- For brightness, this should work I guess... For some reason, contrast is factored into how the luma offset is
	-- calculated on the eq filter, so we need to offset it in a way that the effective offset added is the same.
	-- Also, on mpv's side, we add it after the conversion to RGB; I'm not sure how that affects things but hopefully
	-- it ends in the same result.
	eq_brightness = (mpv_brightness / 50.0 + eq_contrast - 1) / 2.0

	return {"lavfi-eq=contrast=#{eq_contrast}:saturation=#{eq_saturation}:brightness=#{eq_brightness}"}

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
	append_property(ret, "video-rotate")
	append_property(ret, "ytdl-format")
	append_property(ret, "deinterlace")

	return ret

get_sub_options = ->
	ret = {}
	append_property(ret, "sub-ass-override")
	append_property(ret, "sub-ass-style-overrides")
	append_property(ret, "sub-ass-use-video-data")
	append_property(ret, "sub-auto")
	append_property(ret, "sub-pos")
	append_property(ret, "sub-scale")
	append_property(ret, "sub-font")
	append_property(ret, "sub-font-size")
	append_property(ret, "sub-bold")
	append_property(ret, "sub-italic")
	append_property(ret, "sub-color")
	append_property(ret, "sub-back-color")
	append_property(ret, "sub-border-color")
	append_property(ret, "sub-border-size")
	append_property(ret, "sub-shadow-color")
	append_property(ret, "sub-shadow-offset")
	append_property(ret, "sub-use-margins")
	append_property(ret, "sub-margin-x")
	append_property(ret, "sub-margin-y")
	append_property(ret, "sub-align-x")
	append_property(ret, "sub-align-y")
	append_property(ret, "sub-spacing")
	append_property(ret, "sub-justify")
	append_property(ret, "sub-gauss")
	append_property(ret, "sub-gray")

	return ret

-- Handle speed changes
--
-- Two time domains are involved:
--   source  - the user's selection inside the file (sourceStart/sourceEnd)
--   encoder - the timeline mpv's encoder uses, after the filter chain (with
--             possible speed changes) is applied
--
-- mpv's --start and --end options are a little counter-intuitive:
-- 1. --start takes a source time as input and seeks to that point.
-- 2. The filters are applied
-- 3. then the same --start time is used to encode.
-- But if the timeline has changed due to speed filters, the start time is now
-- offset and will be wrong, leading to the wrong part of the video being encoded
-- Same applies for the end time, due to timeline changes the end time can be offset.

-- To fix this, we need to offset the filtered timeline back to the old sourceStart,
-- so the sourceStart time and the encoderStart time are identical.

-- Bundle relevant start/end times & speed
encode_times = (startTime, endTime, speed) ->
	outputDuration = (endTime - startTime) / speed
	{
		sourceStart: startTime
		sourceEnd: endTime
		speed: speed
		encoderStart: startTime -- not scaled, see comment above
		encoderEnd: startTime + outputDuration
		outputDuration: outputDuration
	}

get_speed_video_flags = (times) ->
	if times.speed == 1
		return {}
	-- Rebase both streams to the selection origin, not their first frame/sample,
	-- so an initial A/V offset survives the speed change.
	{
		"--vf-add=trim=start=#{times.sourceStart}:end=#{times.sourceEnd}"
		"--vf-add=setpts=(PTS-#{times.sourceStart}/TB)/#{times.speed}"
		"--vf-add=setpts=PTS+#{times.sourceStart}/TB"
	}

get_speed_audio_flags = (times) ->
	if times.speed == 1
		return {}
	-- libavfilter's atempo only accepts [0.5, 100]; below that it has to be
	-- chained, so that any of mpv's speeds (down to 0.01) works.
	atempo = {}
	tempo = times.speed
	while tempo < 0.5
		atempo[#atempo + 1] = "atempo=0.5"
		tempo *= 2
	atempo[#atempo + 1] = "atempo=#{tempo}"
	-- Scale the initial offset from the shared selection origin before atempo.
	-- atempo changes sample duration but preserves the first input timestamp.
	{
		"--af-add=atrim=start=#{times.sourceStart}:end=#{times.sourceEnd}"
		"--af-add=asetpts=(PTS-#{times.sourceStart}/TB)/#{times.speed}"
		"--af-add=#{table.concat(atempo, ",")}"
		"--af-add=asetpts=PTS+#{times.sourceStart}/TB"
	}

get_sub_speed_flags = (times, source_time = false) ->
	sub_speed = mp.get_property_number("sub-speed", 1)
	sub_delay = mp.get_property_number("sub-delay", 0)
	-- A pre-retiming subtitle filter (GIF) needs the original user settings.
	if times.speed != 1 and not source_time
		-- Project both user adjustments into the encoder timeline.
		sub_speed *= 1 / times.speed
		sub_delay = sub_delay / times.speed + times.sourceStart - times.sourceStart / times.speed
	ret = {}
	append(ret, {"--sub-speed=#{sub_speed}"}) if sub_speed != 1
	append(ret, {"--sub-delay=#{sub_delay}"}) if sub_delay != 0
	return ret

get_metadata_flags = ->
	title = mp.get_property("filename/no-ext")
	return {"--oset-metadata=title=%#{string.len(title)}%#{title}"}

-- Wrap a filter parameter in mpv's raw string syntax so property expansion
-- can't interpret anything inside it.
quote_filter_param = (value) ->
	"%#{string.len(value)}%#{value}"

-- mpv exposes libavfilter bridge filters as "lavfi-<name>" and reports their
-- arguments as positional placeholders (@0, @1, ...) or as regular option
-- names. The placeholder form is only understood by mpv's own option parser,
-- so turn it into a libavfilter-style argument list. Values are left unquoted
-- because the GIF format embeds these filters in a raw graph, where mpv's
-- property expansion (and with it the %N% raw string syntax) does not run.
serialize_lavfi_filter = (filter) ->
	name = filter["name"]
	params = filter["params"] or {}

	if name == "lavfi"
		graph = params["graph"]
		return graph and "#{name}=[#{graph}]" or name

	positional = {}
	named = {}
	for key, value in pairs params
		index = key\match("^@(%d+)$")
		if index
			positional[tonumber(index) + 1] = value
		else
			named[key] = value

	args = {}
	if #positional > 0
		for value in *positional
			append(args, {value})
	else
		keys = [key for key in pairs named]
		table.sort(keys)
		for key in *keys
			append(args, {"#{key}=#{named[key]}"})

	return #args > 0 and "#{name}=#{table.concat(args, ":")}" or name

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
		if str == "lavfi" or str\match("^lavfi%-")
			str = serialize_lavfi_filter(filter)
		else
			for k, v in pairs params
				str = str .. ":#{k}=#{quote_filter_param(v)}"
		append(filters, {str})

get_video_filters = (format, region) ->
	filters = {}
	append(filters, format\getPreFilters!)

	if options.apply_current_filters
		apply_current_filters(filters)

	if region and region\is_valid!
		append(filters, {"lavfi-crop=#{region.w}:#{region.h}:#{region.x}:#{region.y}"})

	append(filters, get_scale_filters!)
	append(filters, get_fps_filters!)
	if options.apply_current_filters
		append(filters, get_contrast_brightness_and_saturation_filters!)

	append(filters, format\getPostFilters!)

	return filters

get_video_encode_flags = (format, region, times) ->
	flags = {}
	append(flags, get_playback_options!)
	append(flags, get_sub_options!)


	filters = get_video_filters(format, region)
	for f in *filters
		append(flags, {
			"--vf-add=#{f}"
		})

	if not format.handlesSpeedInFilterGraph
		append(flags, get_speed_video_flags(times))
	append(flags, get_sub_speed_flags(times, format.rendersSubtitlesInSourceTime))
	return flags

calculate_bitrate = (active_tracks, format, length) ->
	if format.videoCodec == ""
		-- Allocate everything to the audio, not a lot we can do here
		return nil, options.target_filesize * 8 / length
	
	video_kilobits = options.target_filesize * 8
	audio_kilobits = nil
	
	has_audio_track = #active_tracks["audio"] > 0
	if options.strict_filesize_constraint and has_audio_track
		-- We only care about audio bitrate on strict encodes
		audio_kilobits = length * options.strict_audio_bitrate
		video_kilobits -= audio_kilobits
	
	video_bitrate = math.floor(video_kilobits / length)
	audio_bitrate = audio_kilobits and math.floor(audio_kilobits / length) or nil

	return video_bitrate, audio_bitrate

find_path = (startTime, endTime) ->
	path = mp.get_property('path')
	if not path
		return nil, nil, nil, nil, nil
	
	is_stream = not file_exists(path)
	is_temporary = false
	if is_stream
		if mp.get_property('file-format') == 'hls'
			-- Attempt to dump the stream cache into a temporary file
			path = utils.join_path(parse_directory('~'), 'cache_dump.ts')
			mp.command_native({
				'dump_cache',
				seconds_to_time_string(startTime, false, true),
				seconds_to_time_string(endTime + 5, false, true),
				path
			})

			endTime = endTime - startTime
			startTime = 0
			is_temporary = true

	return path, is_stream, is_temporary, startTime, endTime

-- Probe the same executable before entering any launch mode (including the
-- progress shell and detached mode, which otherwise hide spawn failures).
check_encoder = ->
    result = utils.subprocess({args: {"mpv", "--no-config", "--version"}, cancellable: false})
    if result.status == 0
        return true
    explanation = "Cannot start the mpv encoder. Add the folder containing mpv to PATH, then restart the player. See README: Encoder executable."
    if result.status and result.status > 0
        explanation = "The mpv encoder failed its startup check. Run mpv --version and check the logs for details."
    msg.error(explanation)
    msg.error("Encoder startup check: ", result.error or "", result.stderr or "", result.stdout or "")
    message(explanation, 10)
    emit_event("encode-finished", "fail", explanation)
    return false

encode = (region, startTime, endTime, onDone) ->
	format = formats[options.output_format]
	if not check_encoder!
		onDone(false) if onDone
		return

	originalStartTime = startTime
	originalEndTime = endTime
	path, is_stream, is_temporary, startTime, endTime = find_path(startTime, endTime) 
	if not path
		message("No file is being played")
		onDone(false) if onDone
		return

	speed = mp.get_property_native("speed") or 1
	times = encode_times(startTime, endTime, speed)

	command = {
		"mpv", path,
		"--start=" .. seconds_to_time_string(times.encoderStart, false, true),
		"--end=" .. seconds_to_time_string(times.encoderEnd, false, true),
		-- When loop-file=inf, the encode won't end. Set this to override.
		"--loop-file=no",
		-- Same thing with --pause
		"--no-pause"
	}

	append(command, format\getCodecFlags!)

	active_tracks = get_active_tracks!
	supported_active_tracks = filter_tracks_supported_by_format(active_tracks, format)
	for track_type, tracks in pairs supported_active_tracks
		if track_type == "audio"
			append_audio_tracks(command, tracks)
		else
			for track in *tracks
				append_track(command, track)
	
	for track_type, tracks in pairs supported_active_tracks
		if #tracks > 0
			continue
		switch track_type
			when "video"
				append(command, {"--vid=no"})
			when "audio"
				append(command, {"--aid=no"})
			when "sub"
				append(command, {"--sid=no"})

	if format.videoCodec != ""
		-- All those are only valid for video codecs.
		append(command, get_video_encode_flags(format, region, times))

	if format.audioCodec != ""
		append(command, get_speed_audio_flags(times))
	
	append(command, format\getFlags!)

	if options.write_filename_on_metadata
		append(command, get_metadata_flags!)

	if format.acceptsBitrate
		if options.target_filesize > 0
			length = times.outputDuration
			video_bitrate, audio_bitrate = calculate_bitrate(supported_active_tracks, format, length)
			if video_bitrate
				append(command, {
					"--ovcopts-add=b=#{video_bitrate}k",
				})
			
			if audio_bitrate
				append(command, {
					"--oacopts-add=b=#{audio_bitrate}k"
				})
			
			if options.strict_filesize_constraint
				type = format.videoCodec != "" and "ovc" or "oac"
				strict_bitrate = format.videoCodec != "" and video_bitrate or audio_bitrate
				append(command, {
					"--#{type}opts-add=minrate=#{strict_bitrate}k",
					"--#{type}opts-add=maxrate=#{strict_bitrate}k",
				})
		else
			type = format.videoCodec != "" and "ovc" or "oac"
			-- set video bitrate to 0. This might enable constant quality, or some
			-- other encoding modes, depending on the codec.
			append(command, {
				"--#{type}opts-add=b=0"
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

	formatted_filename = format_filename(originalStartTime, originalEndTime, format, dir)
	out_path = utils.join_path(dir, formatted_filename)
	append(command, {"--o=#{out_path}"})

	emit_event("encode-started")

	-- Do the first pass now, as it won't require the output path. I don't think this works on streams.
	-- Also this will ignore run_detached, at least for the first pass.
	-- The current x264/x265 settings cannot use a second pass in constant-quality mode.
	-- Other encoders, including libvpx and libaom, can still use two passes.
	constant_quality_x26x = options.target_filesize <= 0 and (format.videoCodec == "libx264" or format.videoCodec == "libx265")
	if options.twopass and format.supportsTwopass and not constant_quality_x26x and not is_stream
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
			emit_event("encode-finished", "fail")
			onDone(false) if onDone

			return
		
		-- set the second pass flag on the final encode command
		append(command, {
			"--ovcopts-add=flags=+pass2"
		})

		if format.videoCodec == "libvpx"
			-- We need to patch the pass log file before running the second pass.
			msg.verbose("Patching libvpx pass log file...")
			vp8_patch_logfile(get_pass_logfile_path(out_path), times.outputDuration)

	command = format\postCommandModifier(command, region, times)

	msg.info("Encoding to", out_path)
	msg.verbose("Command line:", table.concat(command, " "))

	if options.run_detached and not onDone
		message("Started encode, process was detached.")
		utils.subprocess_detached({args: command})
	else
		res = false
		if not should_display_progress!
			message("Started encode...")
			res = run_subprocess({args: command, cancellable: false})
		else
			ewp = EncodeWithProgress(times.encoderStart, times.encoderEnd)
			res = ewp\startEncode(command)
		if res
			message("Encoded successfully! Saved to\\N#{bold(out_path)}")
			emit_event("encode-finished", "success")
			if options.completion_command != ""
				mp.command(options.completion_command\gsub("%%{output}", out_path))
			onDone(true, out_path) if onDone
		else
			message("Encode failed! Check the logs for details.")
			emit_event("encode-finished", "fail")
			onDone(false) if onDone

		
		-- Clean up pass log file.
		os.remove(get_pass_logfile_path(out_path))
		os.remove "x264_2pass.log"
		os.remove "x264_2pass.log.mbtree"
		if is_temporary
			os.remove(path)
