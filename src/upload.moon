-- Uploading the encoded clip. Only Catbox's two services are supported: both
-- expose the same anonymous multipart API, differing only by endpoint and the
-- required litterbox expiry. streamable.com is intentionally absent: its upload
-- API requires an account (HTTP 401) and its web upload routes 404.
--
-- The POST itself is a single curl call. Asynchronous subprocess runs let the
-- progress page stay responsive while the upload is in flight.

hosts =
	catbox:
		id: "catbox"
		label: "catbox.moe"
		url: "https://catbox.moe/user/api.php"
		time: nil
	litterbox:
		id: "litterbox"
		label: "litterbox.catbox.moe"
		url: "https://litterbox.catbox.moe/resources/internals/api.php"
		time: () -> options.litterbox_time

get_upload_host = (id) ->
	return hosts[id] or hosts.catbox

upload_host_possible_values = () ->
	{{"catbox", "catbox.moe"}, {"litterbox", "litterbox.catbox.moe"}}

-- curl is the only external tool uploads need. Probe it once and cache.
upload_available = nil
is_upload_available = () ->
	if upload_available == nil
		res = utils.subprocess({args: {options.upload_curl_path, "--version"}, playback_only: false})
		upload_available = res != nil and res.status == 0
	return upload_available

-- curl treats comma and semicolon specially inside -F values; escape them so a
-- filename containing either still resolves to a single file.
escape_form_path = (path) ->
	path\gsub("([,;])", "\\%1")

-- The response body (the URL) goes to response_path; curl's progress meter and
-- errors go to progress_path; the HTTP status is printed to stdout.
build_upload_args = (path, host_id, response_path, progress_path) ->
	host = get_upload_host(host_id)
	args = {options.upload_curl_path, "-#", "-S", "-o", response_path,
		"--stderr", progress_path, "-w", "%{http_code}"}
	append(args, {"-F", "reqtype=fileupload"})

	time = host.time
	time = time() if type(time) == "function"
	if time and time != ""
		append(args, {"-F", "time=#{time}"})

	if host.id == "catbox" and options.catbox_userhash != ""
		append(args, {"-F", "userhash=#{options.catbox_userhash}"})

	append(args, {"-F", "fileToUpload=@#{escape_form_path(path)}"})
	append(args, {host.url})
	return args

read_file = (path) ->
	file = io.open(path, "r")
	return nil if not file
	content = file\read("*a")
	file\close!
	return content

is_macos = file_exists("/Applications") and not is_windows

-- Prefer mpv's own clipboard property; fall back to the platform tool when the
-- running mpv is too old to accept writes to clipboard/text. Those tools keep
-- running to own the selection, so they are launched without waiting.
copy_to_clipboard = (text) ->
	ok, written = pcall(() -> mp.set_property("clipboard/text", text))
	return true if ok and written

	candidates = {}
	if is_windows
		candidates = {{"clip"}}
	elseif is_macos
		candidates = {{"pbcopy"}}
	else
		candidates = {{"wl-copy"}, {"xclip", "-selection", "clipboard"}, {"xsel", "--clipboard", "--input"}}

	for args in *candidates
		handle = mp.command_native_async({
			name: "subprocess"
			args: args
			stdin_data: text
			playback_only: false
		}, (-> nil))
		return true if handle
	return false

open_url = (url) ->
	if is_windows
		utils.subprocess_detached({args: {"cmd", "/c", "start", "", url}})
	elseif is_macos
		utils.subprocess_detached({args: {"open", url}})
	else
		utils.subprocess_detached({args: {"xdg-open", url}})
