class AV1QSV extends Format
	new: =>
		@displayName = "AV1 (QSV/AAC)"
		@supportsTwopass = false
		@videoCodec = "av1_qsv"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	getFlags: =>
		{
			"--ovcopts-add=async_depth=#{options.threads}"
		}

	-- Override the CRF flag with QSV's global_quality
	postCommandModifier: (command, region, startTime, endTime) =>
		if options.crf >= 0
			new_cmd = {}
			for arg in *command
				if arg\match("crf=")
					new_cmd[#new_cmd + 1] = "--ovcopts-add=global_quality=#{options.crf}"
				else
					new_cmd[#new_cmd + 1] = arg
			return new_cmd
		return command

formats["av1_qsv"] = AV1QSV!
