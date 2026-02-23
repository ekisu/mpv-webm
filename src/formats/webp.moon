class WebP extends Format
	new: =>
		@displayName = "WebP"
		@supportsTwopass = false
		@videoCodec = "libwebp"
		@audioCodec = ""
		@outputExtension = "webp"
		@acceptsBitrate = false

	getFlags: =>
		qscale = math.max(0, math.min(100, 100 - (options.crf * 2.5)))
		
		{
			"--ovcopts-add=threads=#{options.threads}",
			"--ovcopts-add=compression_level=6",
			"--ovcopts-add=qscale=#{qscale}",
			"--ofopts-add=loop=0"
		}

	postCommandModifier: (command, region, startTime, endTime) =>
		new_command = {}
		for _, v in ipairs command
			if not v\match("^%-%-ovcopts%-add=crf=")
				append(new_command, {v})
		return new_command

formats["webp"] = WebP!
