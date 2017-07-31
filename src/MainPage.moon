class MainPage extends Page
	new: =>
		@keybinds =
			"c": self\crop
			"1": self\setStartTime
			"2": self\setEndTime
			"o": self\changeOptions
			"p": self\preview
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
		ass\append("#{bold('WebM maker')}\\N\\N")
		ass\append("#{bold('c:')} crop\\N")
		ass\append("#{bold('1:')} set start time (current is #{seconds_to_time_string(@startTime)})\\N")
		ass\append("#{bold('2:')} set end time (current is #{seconds_to_time_string(@endTime)})\\N")
		ass\append("#{bold('o:')} change encode options\\N")
		ass\append("#{bold('p:')} preview\\N")
		ass\append("#{bold('e:')} encode\\N\\N")
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

	onPreviewEnded: =>
		self\show!

	preview: =>
		self\hide!
		previewPage = PreviewPage(self\onPreviewEnded, @region, @startTime, @endTime)
		previewPage\show!

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
