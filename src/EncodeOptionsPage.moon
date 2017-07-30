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
		-- TODO this shouldn't be here.
		scaleHeightOpts = {{-1, "no"}, {240}, {360}, {480}, {720}, {1080}, {1440}, {2160}}
		-- This could be a dict instead of a array of pairs, but order isn't guaranteed
		-- by dicts on Lua.
		@options = {
			{"twopass", Option("bool", "Two Pass", options.twopass)},
			{"scale_height", Option("list", "Scale Height", options.scale_height, scaleHeightOpts)},
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
