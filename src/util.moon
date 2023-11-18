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
	time_string, _ = time_string\gsub(":", ".")
	return time_string

file_exists = (name) ->
	info, err = utils.file_info(name)
	if info ~= nil
		return true
	return false

expand_properties = (text, magic="$") ->
	for prefix, raw, prop, colon, fallback, closing in text\gmatch("%" .. magic .. "{([?!]?)(=?)([^}:]*)(:?)([^}]*)(}*)}")
		local err
		local prop_value
		local compare_value
		original_prop = prop
		get_property = mp.get_property_osd

		if raw == "="
			get_property = mp.get_property

		if prefix ~= ""
			for actual_prop, compare in prop\gmatch("(.-)==(.*)")
				prop = actual_prop
				compare_value = compare

		if colon == ":"
			prop_value, err = get_property(prop, fallback)
		else
			prop_value, err = get_property(prop, "(error)")
		prop_value = tostring(prop_value)

		if prefix == "?"
			if compare_value == nil
				prop_value = err == nil and fallback .. closing or ""
			else
				prop_value = prop_value == compare_value and fallback .. closing or ""
			prefix = "%" .. prefix
		elseif prefix == "!"
			if compare_value == nil
				prop_value = err ~= nil and fallback .. closing or ""
			else
				prop_value = prop_value ~= compare_value and fallback .. closing or ""
		else
			prop_value = prop_value .. closing

		if colon == ":"
			text, _ = text\gsub("%" .. magic .. "{" .. prefix .. raw .. original_prop\gsub("%W", "%%%1") .. ":" .. fallback\gsub("%W", "%%%1") .. closing .. "}", expand_properties(prop_value))
		else
			text, _ = text\gsub("%" .. magic .. "{" .. prefix .. raw .. original_prop\gsub("%W", "%%%1") .. closing .. "}", prop_value)

	return text

format_filename = (startTime, endTime, videoFormat) ->
	hasAudioCodec = videoFormat.audioCodec != ""
	replaceFirst =
		"%%mp": "%%mH.%%mM.%%mS"
		"%%mP": "%%mH.%%mM.%%mS.%%mT"
		"%%p": "%%wH.%%wM.%%wS"
		"%%P": "%%wH.%%wM.%%wS.%%wT"
	replaceTable =
		"%%wH": string.format("%02d", math.floor(startTime/(60*60)))
		"%%wh": string.format("%d", math.floor(startTime/(60*60)))
		"%%wM": string.format("%02d", math.floor(startTime/60%60))
		"%%wm": string.format("%d", math.floor(startTime/60))
		"%%wS": string.format("%02d", math.floor(startTime%60))
		"%%ws": string.format("%d", math.floor(startTime))
		"%%wf": string.format("%s", startTime)
		"%%wT": string.sub(string.format("%.3f", startTime%1), 3)
		"%%mH": string.format("%02d", math.floor(endTime/(60*60)))
		"%%mh": string.format("%d", math.floor(endTime/(60*60)))
		"%%mM": string.format("%02d", math.floor(endTime/60%60))
		"%%mm": string.format("%d", math.floor(endTime/60))
		"%%mS": string.format("%02d", math.floor(endTime%60))
		"%%ms": string.format("%d", math.floor(endTime))
		"%%mf": string.format("%s", endTime)
		"%%mT": string.sub(string.format("%.3f", endTime%1), 3)
		"%%f": mp.get_property("filename")
		"%%F": mp.get_property("filename/no-ext")
		"%%s": seconds_to_path_element(startTime)
		"%%S": seconds_to_path_element(startTime, true)
		"%%e": seconds_to_path_element(endTime)
		"%%E": seconds_to_path_element(endTime, true)
		"%%T": mp.get_property("media-title")
		"%%M": (mp.get_property_native('aid') and not mp.get_property_native('mute') and hasAudioCodec) and '-audio' or ''
		"%%R": (options.scale_height != -1) and "-#{options.scale_height}p" or "-#{mp.get_property_native('height')}p"
		"%%mb": options.target_filesize/1000
		"%%t%%": "%%"
	filename = options.output_template

	for format, value in pairs replaceFirst
		filename, _ = filename\gsub(format, value)
	for format, value in pairs replaceTable
		filename, _ = filename\gsub(format, value)

	if mp.get_property_bool("demuxer-via-network", false)
		filename, _ = filename\gsub("%%X{([^}]*)}", "%1")
		filename, _ = filename\gsub("%%x", "")
	else
		x = string.gsub(mp.get_property("stream-open-filename", ""), string.gsub(mp.get_property("filename", ""), "%W", "%%%1") .. "$", "")
		filename, _ = filename\gsub("%%X{[^}]*}", x)
		filename, _ = filename\gsub("%%x", x)

	filename = expand_properties(filename, "%")

	for format in filename\gmatch("%%t([aAbBcCdDeFgGhHIjmMnprRStTuUVwWxXyYzZ])")
		filename, _ = filename\gsub("%%t" .. format, os.date("%" .. format))

	-- Remove invalid chars
	-- Windows: < > : " / \ | ? *
	-- Linux: /
	filename, _ = filename\gsub("[<>:\"/\\|?*]", "")

	return "#{filename}.#{videoFormat.outputExtension}"

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

-- from stats.lua
is_windows = type(package) == "table" and type(package.config) == "string" and package.config\sub(1, 1) == "\\"

trim = (s) ->
	return s\match("^%s*(.-)%s*$")

get_null_path = ->
	if file_exists("/dev/null")
		return "/dev/null"
	return "NUL"

run_subprocess = (params) ->
	res = utils.subprocess(params)
	msg.verbose("Command stdout: ")
	msg.verbose(res.stdout)
	if res.status != 0
		msg.verbose("Command failed! Reason: ", res.error, " Killed by us? ", res.killed_by_us and "yes" or "no")
		return false
	return true

shell_escape = (args) ->
	ret = {}
	for i,a in ipairs(args)
		s = tostring(a)
		if string.match(s, "[^A-Za-z0-9_/:=-]")
			-- Single quotes for UNIX, double quotes for Windows.
			if is_windows
				s = '"'..string.gsub(s, '"', '"\\""')..'"'
			else
				s = "'"..string.gsub(s, "'", "'\\''").."'"
		table.insert(ret,s)
	concat = table.concat(ret, " ")
	if is_windows
		-- Add a second set of double-quotes because idk it works
		concat = '"' .. concat .. '"'
	return concat

run_subprocess_popen = (command_line) ->
	command_line_string = shell_escape(command_line)
	-- Redirect stderr to stdout, because for some reason
	-- the progress is outputted to stderr???
	command_line_string ..= " 2>&1"
	msg.verbose("run_subprocess_popen: running #{command_line_string}")
	return io.popen(command_line_string)

calculate_scale_factor = () ->
	baseResY = 720
	osd_w, osd_h = mp.get_osd_size()
	return osd_h / baseResY

should_display_progress = () ->
	if options.display_progress == "auto"
		return not is_windows
	return options.display_progress

reverse = (list) ->
	[element for element in *list[#list, 1, -1]]

get_pass_logfile_path = (encode_out_path) ->
	"#{encode_out_path}-video-pass1.log"
