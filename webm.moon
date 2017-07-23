mp = require "mp"
assdraw = require "mp.assdraw"
msg = require "mp.msg"
utils = require "mp.utils"
mpopts = require "mp.options"

options =
	-- Defaults to shift+w
	keybind: "W"
	-- If empty, saves on the same directory of the playing video.
	-- A starting "~" will be replaced by the home dir.
	output_directory: ""
	run_detached: false
	-- Format string for the output file
	-- %f - Filename, with extension
	-- %F - Filename, without extension
	-- %T - Media title, if it exists, or filename, with extension (useful for some streams, such as YouTube).
	-- %s, %e - Start and end time, with milliseconds
	-- %S, %E - Start and time, without milliseconds
	-- %M - "-audio", if audio is enabled, empty otherwise
	output_format: "%F-[%s-%e]%M"
	-- Scale video to a certain height, keeping the aspect ratio. -1 disables it.
	scale_height: -1
	-- Target filesize, in kB.
	target_filesize: 2500
	-- If true, will use stricter flags to ensure the resulting file doesn't
	-- overshoot the target filesize. Not recommended, as constrained quality
	-- mode should work well, unless you're really having trouble hitting
	-- the target size.
	strict_filesize_constraint: false
	strict_bitrate_multiplier: 0.95
	-- In kilobits.
	strict_audio_bitrate: 64
	video_codec: "libvpx"
	audio_codec: "libvorbis"
	twopass: true
	-- Set the number of encoding threads, for codecs libvpx and libvpx-vp9
	libvpx_threads: 4
	additional_flags: "--sub=no"
	-- Useful for flags that may impact output filesize, such as crf, qmin, qmax etc
	-- Won't be applied when strict_filesize_constraint is on.
	non_strict_additional_flags: "--ovcopts-add=crf=10"
	-- Only encode tracks that are actually playing
	only_active_tracks: true
	-- If subs are visible, will attempt to 'burn' the subs into the resulting video.
	-- Haven't tested with external subs, but it should? work.
	hardsub: true
	output_extension: "webm"
	-- The font size used in the menu. Isn't used for the notifications (started encode, finished encode etc)
	font_size: 24
	margin: 10
	message_duration: 5

mpopts.read_options(options)

bold = (text) ->
	"{\\b1}#{text}{\\b0}"

-- OSD message, using ass.
message = (text, duration) ->
	ass = mp.get_property_osd("osd-ass-cc/0")
	-- wanted to set font size here, but it's completely unrelated to the font
	-- size in set_osd_ass.
	ass ..= text
	mp.osd_message(ass, duration or options.message_duration)

append = (a, b) ->
	for _, val in ipairs b
		a[#a+1] = val
	return a

-- most functions were shamelessly copypasted from occivink's mpv-scripts, changed to moonscript syntax
dimensions_changed = true
_video_dimensions = {}
get_video_dimensions = ->
	return _video_dimensions unless dimensions_changed

	-- this function is very much ripped from video/out/aspect.c in mpv's source
	video_params = mp.get_property_native("video-out-params")
	return nil if not video_params

	dimensions_changed = false
	keep_aspect = mp.get_property_bool("keepaspect")
	w = video_params["w"]
	h = video_params["h"]
	dw = video_params["dw"]
	dh = video_params["dh"]
	if mp.get_property_number("video-rotate") % 180 == 90
		w, h = h, w
		dw, dh = dh, dw
	
	_video_dimensions = {
		top_left: {},
		bottom_right: {},
		ratios: {},
	}
	window_w, window_h = mp.get_osd_size()

	if keep_aspect
		unscaled = mp.get_property_native("video-unscaled")
		panscan = mp.get_property_number("panscan")

		fwidth = window_w
		fheight = math.floor(window_w / dw * dh)
		if fheight > window_h or fheight < h
			tmpw = math.floor(window_h / dh * dw)
			if tmpw <= window_w
				fheight = window_h
				fwidth = tmpw
		vo_panscan_area = window_h - fheight
		f_w = fwidth / fheight
		f_h = 1
		if vo_panscan_area == 0
			vo_panscan_area = window_h - fwidth
			f_w = 1
			f_h = fheight / fwidth

		if unscaled or unscaled == "downscale-big"
			vo_panscan_area = 0
			if unscaled or (dw <= window_w and dh <= window_h)
				fwidth = dw
				fheight = dh

		scaled_width = fwidth + math.floor(vo_panscan_area * panscan * f_w)
		scaled_height = fheight + math.floor(vo_panscan_area * panscan * f_h)

		split_scaling = (dst_size, scaled_src_size, zoom, align, pan) ->
			scaled_src_size = math.floor(scaled_src_size * 2 ^ zoom)
			align = (align + 1) / 2
			dst_start = math.floor((dst_size - scaled_src_size) * align + pan * scaled_src_size)
			if dst_start < 0
				--account for C int cast truncating as opposed to flooring
				dst_start = dst_start + 1
			dst_end = dst_start + scaled_src_size
			if dst_start >= dst_end
				dst_start = 0
				dst_end = 1
			return dst_start, dst_end

		zoom = mp.get_property_number("video-zoom")

		align_x = mp.get_property_number("video-align-x")
		pan_x = mp.get_property_number("video-pan-x")
		_video_dimensions.top_left.x, _video_dimensions.bottom_right.x = split_scaling(window_w, scaled_width, zoom, align_x, pan_x)

		align_y = mp.get_property_number("video-align-y")
		pan_y = mp.get_property_number("video-pan-y")
		_video_dimensions.top_left.y, _video_dimensions.bottom_right.y = split_scaling(window_h,  scaled_height, zoom, align_y, pan_y)
	else
		_video_dimensions.top_left.x = 0
		_video_dimensions.bottom_right.x = window_w
		_video_dimensions.top_left.y = 0
		_video_dimensions.bottom_right.y = window_h

	_video_dimensions.ratios.w = w / (_video_dimensions.bottom_right.x - _video_dimensions.top_left.x)
	_video_dimensions.ratios.h = h / (_video_dimensions.bottom_right.y - _video_dimensions.top_left.y)
	return _video_dimensions

set_dimensions_changed = () ->
	dimensions_changed = true

clamp = (min, val, max) ->
	return min if val <= min
	return max if val >= max
	return val

clamp_point = (top_left, point, bottom_right) ->
	{
		x: clamp(top_left.x, point.x, bottom_right.x),
		y: clamp(top_left.y, point.y, bottom_right.y)
	}

seconds_to_time_string = (seconds, no_ms, full) ->
	if seconds < 0
		return "unknown"
	ret = ""
	ret = string.format(".%03d", seconds * 1000 % 1000) unless no_ms
	ret = string.format("%02d:%02d%s", math.floor(seconds / 60) % 60, math.floor(seconds) % 60, ret)
	if full or seconds > 3600
		ret = string.format("%d:%s", math.floor(seconds / 3600), ret)
	ret

seconds_to_path_element = (seconds, no_ms, full) ->
	time_string = seconds_to_time_string(seconds, no_ms, full)
	-- Needed for Windows (and maybe for Linux? idk)
	time_string, _ = time_string\gsub(":", "_")
	return time_string

file_exists = (name) ->
	f = io.open(name, "r")
	if f ~= nil
		io.close(f)
		return true
	return false

-- Stores a point in the video, relative to the source resolution.
class VideoPoint
	new: =>
		@x = -1
		@y = -1

	set_from_screen: (sx, sy) =>
		d = get_video_dimensions!
		point = clamp_point(d.top_left, {x: sx, y: sy}, d.bottom_right)
		@x = math.floor(d.ratios.w * (point.x - d.top_left.x) + 0.5)
		@y = math.floor(d.ratios.h * (point.y - d.top_left.y) + 0.5)

	to_screen: =>
		d = get_video_dimensions!
		return {
			x: math.floor(@x / d.ratios.w + d.top_left.x + 0.5),
			y: math.floor(@y / d.ratios.h + d.top_left.y + 0.5)
		}

class Region
	new: =>
		@x = -1
		@y = -1
		@w = -1
		@h = -1

	is_valid: =>
		@x > -1 and @y > -1 and @w > -1 and @h > -1

	set_from_points: (p1, p2) =>
		@x = math.min(p1.x, p2.x)
		@y = math.min(p1.y, p2.y)
		@w = math.abs(p1.x - p2.x)
		@h = math.abs(p1.y - p2.y)

-- Encoding code --
format_filename = (startTime, endTime) ->
	replaceTable =
		"%%f": mp.get_property("filename")
		"%%F": mp.get_property("filename/no-ext")
		"%%s": seconds_to_path_element(startTime)
		"%%S": seconds_to_path_element(startTime, true)
		"%%e": seconds_to_path_element(endTime)
		"%%E": seconds_to_path_element(endTime, true)
		"%%T": mp.get_property("media-title")
		"%%M": (mp.get_property_native('aid') and not mp.get_property_native('mute')) and '-audio' or ''
	filename = options.output_format

	for format, value in pairs replaceTable
		filename, _ = filename\gsub(format, value)

	-- Remove invalid chars
	-- Windows: < > : " / \ | ? *
	-- Linux: /
	filename, _ = filename\gsub("[<>:\"/\\|?*]", "")

	return "#{filename}.#{options.output_extension}"

parse_directory = (dir) ->
	home_dir = os.getenv("HOME")
	if not home_dir
		-- Windows home dir is obtained by USERPROFILE, or, if it fails, HOMEDRIVE + HOMEPATH
		home_dir = os.getenv("USERPROFILE")

	if not home_dir
		drive = os.getenv("HOMEDRIVE")
		path = os.getenv("HOMEPATH")
		if drive and path
			home_dir = utils.join_path(drive, path)
		else
			msg.warn("Couldn't find home dir.")
			home_dir = ""
	dir, _ = dir\gsub("^~", home_dir)
	return dir

get_null_path = ->
	if file_exists("/dev/null")
		return "/dev/null"
	return "NUL"

-- mpv also requires escaping, but, for some reason, the ffmpeg one won't work
-- this one is more of a hack than an actual solution, but it works.
-- also requires lavfi to be used.
escape_filter_path = (path) ->
	-- replace backslashes with forward slashes.
	path = path\gsub("\\", "/")
	-- escape :[],; chars
	path = path\gsub("([:[,;])", "\\%1")
	-- i can't figure out how to escape ] in the regex above, so escape it separately
	path = path\gsub("(])", "\\%1")
	return path

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

get_subtitle_filters = (path) ->
	return {} unless options.hardsub and mp.get_property_bool("sub-visibility")

	-- Store the embedded sub index.
	-- This relies on mpv storing sub tracks in the same order as the source file.
	sub_index = -1
	for _, track in ipairs mp.get_property_native("track-list")
		sub_index += 1 if track["type"] == "sub" and not track["external"]
		if track["selected"] and track["type"] == "sub"
			if track["external"]
				return {"subtitles='#{escape_filter_path(track['external-filename'])}'"}
			else
				-- not sure if track[id] or track[src-id] should be used.
				return {"subtitles='#{escape_filter_path(path)}':si=#{sub_index}"}

	-- No subs found, or subs aren't enabled.
	return {}

get_color_conversion_filters = ->
	-- supported conversions
	colormatrixFilter =
		"bt.709": "bt709"
		"bt.2020": "bt2020"
	ret = {}
	-- vp8 only supports bt.601, so add a conversion filter
	-- thanks anon
	colormatrix = mp.get_property_native("video-params/colormatrix")
	if options.video_codec == "libvpx" and colormatrixFilter[colormatrix]
		append(ret, {
			"colormatrix=#{colormatrixFilter[colormatrix]}:bt601"
		})
	return ret

get_scale_filters = ->
	if options.scale_height > 0
		return {"scale=-1:#{options.scale_height}"}
	return {}

encode = (region, startTime, endTime) ->
	path = mp.get_property("path")
	if not path
		message("No file is being played")
		return

	is_stream = not file_exists(path)

	command = {
		"mpv", path,
		"--start=" .. seconds_to_time_string(startTime, false, true),
		"--end=" .. seconds_to_time_string(endTime, false, true),
		"--ovc=#{options.video_codec}",	"--oac=#{options.audio_codec}"
	}

	vid = -1
	aid = -1
	sid = -1
	if options.only_active_tracks
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

	filters = {}

	append(filters, get_color_conversion_filters!)
	append(filters, get_subtitle_filters(path))

	if region and region\is_valid!
		append(filters, {"crop=#{region.w}:#{region.h}:#{region.x}:#{region.y}"})

	append(filters, get_scale_filters!)

	if #filters > 0
		append(command, {
			-- Need lavfi to make the escaping done on get_subtitle_filter work.
			"--vf", "lavfi=[#{table.concat(filters, ',')}]"
		})

	if options.video_codec == "libvpx" or options.audio_codec == "libvpx-vp9"
		append(command, {
			"--ovcopts-add=threads=#{options.libvpx_threads}"
		})

	if options.target_filesize > 0
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
	if options.twopass and not is_stream
		-- copy the commandline
		first_pass_cmdline = [arg for arg in *command]
		append(first_pass_cmdline, {
			"--ovcopts-add=flags=+pass1",
			"-of=#{options.output_extension}",
			"-o=#{get_null_path!}"
		})
		message("Starting first pass...")
		msg.verbose("First-pass command line: ", table.concat(first_pass_cmdline, " "))
		res = utils.subprocess({args: first_pass_cmdline, cancellable: false})
		if res.status != 0
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
	
	formatted_filename = format_filename(startTime, endTime)
	out_path = utils.join_path(dir, formatted_filename)
	append(command, {"-o=#{out_path}"})

	msg.info("Encoding to", out_path)
	msg.verbose("Command line:", table.concat(command, " "))

	if options.run_detached
		message("Started encode, process was detached.")
		utils.subprocess_detached({args: command})
	else
		message("Started encode...")
		res = utils.subprocess({args: command, cancellable: false})
		if res.status == 0
			message("Encoded successfully! Saved to\\N#{bold(out_path)}")
		else
			message("Encode failed! Check the logs for details.")

-- UI Code --
class Page
	add_keybinds: =>
		for key, func in pairs @keybinds
			mp.add_forced_key_binding(key, key, func, {repeatable: true})

	remove_keybinds: =>
		for key, _ in pairs @keybinds
			mp.remove_key_binding(key)

	clear: =>
		window_w, window_h = mp.get_osd_size()
		mp.set_osd_ass(window_w, window_h, "")
		mp.osd_message("", 0)

	prepare: =>
		nil

	dispose: =>
		nil

	show: =>
		@visible = true
		self\add_keybinds!
		self\prepare!
		self\clear!
		self\draw!

	hide: =>
		@visible = false
		self\remove_keybinds!
		self\clear!
		self\dispose!

	setup_text: (ass) =>
		ass\pos(options.margin, options.margin)
		ass\append("{\\fs#{options.font_size}}")

class CropPage extends Page
	new: (callback, region) =>
		@pointA = VideoPoint!
		@pointB = VideoPoint!
		@keybinds =
			"1": self\setPointA
			"2": self\setPointB
			"r": self\reset
			"ESC": self\cancel
			"ENTER": self\finish
		self\reset!
		@callback = callback
		-- If we have a region, set point A and B from it
		if region and region\is_valid!
			@pointA.x = region.x
			@pointA.y = region.y
			@pointB.x = region.x + region.w
			@pointB.y = region.y + region.h

	reset: =>
		dimensions = get_video_dimensions!
		{x: xa, y: ya} = dimensions.top_left
		@pointA\set_from_screen(xa, ya)
		{x: xb, y: yb} = dimensions.bottom_right
		@pointB\set_from_screen(xb, yb)

		if @visible
			self\draw!

	setPointA: =>
		posX, posY = mp.get_mouse_pos()
		@pointA\set_from_screen(posX, posY)
		if @visible
			-- No need to clear, as we draw the entire OSD (also it causes flickering)
			self\draw!

	setPointB: =>
		posX, posY = mp.get_mouse_pos()
		@pointB\set_from_screen(posX, posY)
		if @visible
			self\draw!

	cancel: =>
		self.callback(false, nil)

	finish: =>
		region = Region!
		region\set_from_points(@pointA, @pointB)
		self.callback(true, region)

	prepare: =>
		-- Monitor these properties, as they affect the video dimensions.
		-- Set the dimensions-changed flag when they change.
		properties = {
			"keepaspect",
			"video-out-params",
			"video-unscaled",
			"panscan",
			"video-zoom",
			"video-align-x",
			"video-pan-x",
			"video-align-y",
			"video-pan-y",
			"osd-width",
			"osd-height",
		}
		for _, p in ipairs(properties)
			mp.observe_property(p, "native", set_dimensions_changed)

	dispose: =>
		mp.unobserve_property(set_dimensions_changed)

	draw_box: (ass) =>
		region = Region!
		region\set_from_points(@pointA\to_screen!, @pointB\to_screen!)

		d = get_video_dimensions!
		ass\new_event()
		ass\pos(0, 0)
		ass\append('{\\bord0}')
		ass\append('{\\shad0}')
		ass\append('{\\c&H000000&}')
		ass\append('{\\alpha&H77}')
		-- Draw a black layer over the uncropped area
		ass\draw_start()
		ass\rect_cw(d.top_left.x, d.top_left.y, region.x, region.y + region.h) -- Top left uncropped area
		ass\rect_cw(region.x, d.top_left.y, d.bottom_right.x, region.y) -- Top right uncropped area
		ass\rect_cw(d.top_left.x, region.y + region.h, region.x + region.w, d.bottom_right.y) -- Bottom left uncropped area
		ass\rect_cw(region.x + region.w, region.y, d.bottom_right.x, d.bottom_right.y) -- Bottom right uncropped area
		ass\draw_stop()

	draw: =>
		window = {}
		window.w, window.h = mp.get_osd_size()
		ass = assdraw.ass_new()
		self\draw_box(ass)
		ass\new_event()
		self\setup_text(ass)
		ass\append("#{bold('Crop:')}\\N")
		ass\append("#{bold('1:')} change point A (#{@pointA.x}, #{@pointA.y})\\N")
		ass\append("#{bold('2:')} change point B (#{@pointB.x}, #{@pointB.y})\\N")
		ass\append("#{bold('r:')} reset to whole screen\\N")
		ass\append("#{bold('ESC:')} cancel crop\\N")
		ass\append("#{bold('ENTER:')} confirm crop\\N")
		mp.set_osd_ass(window.w, window.h, ass.text)

class Option
	-- If optType is a "bool", @value is the boolean value of the option
	-- If optType is a "list", @value is the index of the current option, inside possibleValues.
	-- possibleValues is a array in the format
	-- {
	--		{value, displayValue}, -- Display value can be omitted.
	-- 		{value}	
	-- }
	-- setValue will be called for the constructor argument.
	new: (optType, displayText, value, possibleValues) =>
		@optType = optType
		@displayText = displayText
		@possibleValues = possibleValues
		@value = 1
		self\setValue(value)

	leftKey: =>
		switch @optType
			when "bool"
				@value = not @value
			when "list"
				@value -= 1 if @value > 1

	rightKey: =>
		switch @optType
			when "bool"
				@value = not @value
			when "list"
				@value += 1 if @value < #@possibleValues

	getValue: =>
		switch @optType
			when "bool"
				return @value
			when "list"
				{value, _} = @possibleValues[@value]
				return value

	setValue: (value) =>
		switch @optType
			when "bool"
				@value = value
			when "list"
				set = false
				for i, possiblePair in ipairs @possibleValues
					{possibleValue, _} = possiblePair
					if possibleValue == value
						set = true
						@value = i
						break
				if not set
					msg.warn("Tried to set invalid value #{value} to #{@displayText} option.")

	getDisplayValue: =>
		switch @optType
			when "bool"
				return @value and "yes" or "no"
			when "list"
				{value, displayValue} = @possibleValues[@value]
				return displayValue or value

	draw: (ass, selected) =>
		if selected
			ass\append("#{bold(@displayText)}: ")
		else
			ass\append("#{@displayText}: ")
		-- left arrow unicode
		ass\append("◀ ") if @optType == "bool" or @value > 1
		ass\append(self\getDisplayValue!)
		-- right arrow unicode
		ass\append(" ▶") if @optType == "bool" or @value < #@possibleValues
		ass\append("\\N")

class EncodeOptionsPage extends Page
	new: (callback) =>
		@callback = callback
		@currentOption = 1
		scaleHeightOpts = {{-1, "no"}, {240}, {360}, {480}, {720}, {1080}, {1440}, {2160}}
		@options = {
			{"twopass", Option("bool", "Two Pass", options.twopass)},
			{"scale_height", Option("list", "Scale Height", options.scale_height, scaleHeightOpts)},
			{"hardsub", Option("bool", "Hardsub", options.hardsub)},
			{"strict_filesize_constraint", Option("bool", "Strict Filesize Constraint", options.strict_filesize_constraint)}
		}

		@keybinds =
			"LEFT": self\leftKey
			"RIGHT": self\rightKey
			"UP": self\prevOpt
			"DOWN": self\nextOpt
			"ENTER": self\confirmOpts
			"ESC": self\cancelOpts

	getCurrentOption: =>
		return @options[@currentOption][2]

	leftKey: =>
		(self\getCurrentOption!)\leftKey!
		self\draw!

	rightKey: =>
		(self\getCurrentOption!)\rightKey!
		self\draw!

	prevOpt: =>
		@currentOption = math.max(1, @currentOption - 1)
		self\draw!

	nextOpt: =>
		@currentOption = math.min(#@options, @currentOption + 1)
		self\draw!

	confirmOpts: =>
		for _, optPair in ipairs @options
			{optName, opt} = optPair
			-- Set the global options object.
			options[optName] = opt\getValue!
		self\hide!
		self.callback(true)

	cancelOpts: =>
		self\hide!
		self.callback(false)

	draw: =>
		window_w, window_h = mp.get_osd_size()
		ass = assdraw.ass_new()
		ass\new_event()
		self\setup_text(ass)
		ass\append("#{bold('Options:')}\\N\\N")
		for i, optPair in ipairs @options
			opt = optPair[2]
			opt\draw(ass, @currentOption == i)
		ass\append("\\N▲ / ▼: navigate\\N")
		ass\append("#{bold('ENTER:')} confirm options\\N")
		ass\append("#{bold('ESC:')} cancel\\N")
		mp.set_osd_ass(window_w, window_h, ass.text)

class MainPage extends Page
	new: =>
		@keybinds =
			"c": self\crop
			"1": self\setStartTime
			"2": self\setEndTime
			"o": self\changeOptions
			"e": self\encode
			"ESC": self\hide
		@startTime = -1
		@endTime = -1
		@region = Region!

	setStartTime: =>
		@startTime = mp.get_property_number("time-pos")
		if @visible
			self\clear!
			self\draw!

	setEndTime: =>
		@endTime = mp.get_property_number("time-pos")
		if @visible
			self\clear!
			self\draw!

	draw: =>
		window_w, window_h = mp.get_osd_size()
		ass = assdraw.ass_new()
		ass\new_event()
		self\setup_text(ass)
		ass\append("WebM maker\\N")
		ass\append("#{bold('c:')} crop\\N")
		ass\append("#{bold('1:')} set start time (current is #{seconds_to_time_string(@startTime)})\\N")
		ass\append("#{bold('2:')} set end time (current is #{seconds_to_time_string(@endTime)})\\N")
		ass\append("#{bold('o:')} change encode options\\N")
		ass\append("#{bold('e:')} encode\\N")
		ass\append("#{bold('ESC:')} close\\N")
		mp.set_osd_ass(window_w, window_h, ass.text)

	onUpdateCropRegion: (updated, newRegion) =>
		if updated
			@region = newRegion
		self\show!

	crop: =>
		self\hide!
		cropPage = CropPage(self\onUpdateCropRegion, @region)
		cropPage\show!

	onOptionsChanged: (updated) =>
		self\show!

	changeOptions: =>
		self\hide!
		encodeOptsPage = EncodeOptionsPage(self\onOptionsChanged)
		encodeOptsPage\show!

	encode: =>
		self\hide!
		if @startTime < 0
			message("No start time, aborting")
			return
		if @endTime < 0
			message("No end time, aborting")
			return
		if @startTime >= @endTime
			message("Start time is ahead of end time, aborting")
			return
		encode(@region, @startTime, @endTime)

mainPage = MainPage!
mp.add_key_binding(options.keybind, "display-webm-encoder", mainPage\show, {repeatable: false})
