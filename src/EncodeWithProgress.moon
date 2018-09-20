-- Not really a Page, but reusing its functions is pretty useful
class EncodeWithProgress extends Page
	new: (startTime, endTime) =>
		@startTime = startTime
		@endTime = endTime
		@duration = endTime - startTime
		@currentTime = startTime

	draw: =>
		progress = 100 * ((@currentTime - @startTime) / @duration)
		progressText = string.format("%d%%", progress)
		window_w, window_h = mp.get_osd_size()
		ass = assdraw.ass_new()
		ass\new_event()
		self\setup_text(ass)
		ass\append("Encoding (#{bold(progressText)})\\N")
		mp.set_osd_ass(window_w, window_h, ass.text)

	parseLine: (line) =>
		matchTime = string.match(line, "Encode time[-]pos: ([0-9.]+)")
		matchExit = string.match(line, "Exiting... [(]([%a ]+)[)]")
		if matchTime == nil and matchExit == nil
			return
		
		if matchTime != nil and tonumber(matchTime) > @currentTime -- sometimes we get timestamps older than before...
			@currentTime = tonumber(matchTime)
		if matchExit != nil
			@finished = true
			@finishedReason = matchExit

	startEncode: (command_line) =>
		copy_command_line = [arg for arg in *command_line]
		tmpFilename = "webm_encode_output"
		msg.verbose("Temporary file: #{tmpFilename}")
		append(copy_command_line, { '--term-status-msg=Encode time-pos: ${=time-pos}' })
		self\show!
		outputFd = io.open(tmpFilename, "w+")
		processFd = run_subprocess_popen_output_to_file(copy_command_line, tmpFilename)
		while not @finished
			line = outputFd\read("*l")
			if line == nil
				continue
			msg.verbose("Output: #{line}")
			self\parseLine(line)
			self\draw!
		outputFd\close()
		processFd\close()
		os.remove(tmpFilename)
		self\hide!

		-- This is what we want
		if @finishedReason == "End of file"
			return true
		return false
