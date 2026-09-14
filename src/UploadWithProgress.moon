-- Progress, done and failed states for a single upload. Not an encode page: it
-- runs the curl subprocess asynchronously so ESC can abort it and the progress
-- percentage keeps redrawing.
class UploadWithProgress extends Page
	-- callback(state) where state is "done", "failed", "cancelled" or "options".
	new: (callback, path) =>
		@callback = callback
		@path = path
		_, @filename = utils.split_path(path)
		info = utils.file_info(path)
		@sizeText = info and string.format("%.1f MB", info.size / 1000000) or "unknown size"
		@responsePath = os.tmpname()
		@progressPath = os.tmpname()
		@state = "uploading"
		@percent = 0
		@finished = false
		@cancelled = false
		@keybinds =
			"ESC": self\onEscape
			"c": self\copyAgain
			"o": self\openSomething
			"r": self\retry

	prepare: =>
		self\startUpload!

	dispose: =>
		self\stopTimer!
		os.remove(@responsePath) if @responsePath
		os.remove(@progressPath) if @progressPath

	stopTimer: =>
		if @timer
			@timer\kill!
			@timer = nil

	startUpload: =>
		@state = "uploading"
		@percent = 0
		@finished = false
		@cancelled = false
		@host = get_upload_host(options.upload_host)

		-- Clear a stale progress meter from a previous attempt.
		file = io.open(@progressPath, "w")
		file\close! if file

		args = build_upload_args(@path, options.upload_host, @responsePath, @progressPath)
		@timer = mp.add_periodic_timer(0.2, self\pollProgress)
		@handle = mp.command_native_async({
			name: "subprocess"
			args: args
			playback_only: false
			capture_stdout: true
			capture_stderr: false
			capture_size: 128
		}, self\onFinished)

	pollProgress: =>
		return if @state != "uploading"
		content = read_file(@progressPath)
		return if not content or content == ""
		percent = nil
		for match in content\gmatch("(%d+%.?%d*)%%")
			percent = tonumber(match)
		if percent and math.floor(percent) != @percent
			@percent = math.floor(percent)
			self\draw!

	onFinished: (success, result, error) =>
		return if @finished
		@finished = true
		self\stopTimer!

		if @cancelled
			emit_event("upload-finished", "cancelled")
			self\finish("cancelled")
			return

		httpCode = result and tonumber(result.stdout)
		response = trim(read_file(@responsePath) or "")
		uploadOk = success and result and result.status == 0 and
			httpCode and httpCode >= 200 and httpCode < 300 and
			response\match("^https?://")

		if uploadOk
			@url = response
			@state = "done"
			pcall(() -> copy_to_clipboard(@url))
			pcall(() -> open_url(@url)) if options.open_after_upload
		else
			@state = "failed"
			@errorMessage = response
			if @errorMessage == ""
				@errorMessage = (result and result.error_string) or tostring(error) or "upload failed"
			@errorMessage = @errorMessage\gsub("%s+", " ")\sub(1, 300)
		emit_event("upload-finished", @state)
		self\draw!

	onEscape: =>
		if @state == "uploading"
			@cancelled = true
			self\stopTimer!
			mp.abort_async_command(@handle) if @handle
			-- If the abort never reports back, close anyway.
			mp.add_timeout(0.5, (-> self\finish("cancelled") if not @closing))
		else
			self\finish(@state)

	-- Only meaningful on the done page.
	copyAgain: =>
		if @state == "done" and @url
			copy_to_clipboard(@url)
			message("Link copied to clipboard.")

	-- Open the result on the done page; jump to the options on the failed page.
	openSomething: =>
		if @state == "done" and @url
			open_url(@url)
		elseif @state == "failed"
			self\finish("options")

	retry: =>
		self\startUpload! if @state == "failed"

	finish: (state) =>
		return if @closing
		@closing = true
		self\hide!
		@callback(state)

	draw: =>
		window_w, window_h = mp.get_osd_size()
		ass = assdraw.ass_new()
		ass\new_event()
		self\setup_text(ass)
		if @state == "uploading"
			ass\append("Uploading (#{bold("#{@percent}%")})\\N")
			ass\append("#{@filename}\\N")
			ass\append("#{@sizeText} to #{@host.label}\\N\\N")
			ass\append("#{bold('ESC:')} cancel upload\\N")
		elseif @state == "done"
			ass\append("#{bold('Upload complete')}\\N\\N")
			ass\append("#{@url}\\N")
			ass\append("Link copied to clipboard.\\N\\N")
			ass\append("#{bold('c:')} copy link again\\N")
			ass\append("#{bold('o:')} open in browser\\N")
			ass\append("#{bold('ESC:')} close\\N")
		elseif @state == "failed"
			ass\append("#{bold('Upload failed')}\\N\\N")
			ass\append("#{@errorMessage}\\N")
			ass\append("The clip is still saved locally.\\N\\N")
			ass\append("#{bold('r:')} retry upload\\N")
			ass\append("#{bold('o:')} change upload options\\N")
			ass\append("#{bold('ESC:')} close\\N")
		mp.set_osd_ass(window_w, window_h, ass.text)
