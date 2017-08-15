class PreviewPage extends Page
	new: (callback, region, startTime, endTime) =>
		@callback = callback
		@originalProperties =
			"vf": mp.get_property_native("vf")
			"time-pos": mp.get_property_native("time-pos")
			"pause": mp.get_property_native("pause")

		@keybinds =
			"ESC": self\cancel

		@region = region
		@startTime = startTime
		@endTime = endTime
		@isLoop = false

	prepare: =>
		vf = mp.get_property_native("vf")
		-- Place sub rendering before crop in the filter chain.
		vf[#vf + 1] = {name: "sub"}
		if @region\is_valid!
			vf[#vf + 1] =
				name: "crop"
				params:
					w: tostring(@region.w)
					h: tostring(@region.h)
					x: tostring(@region.x)
					y: tostring(@region.y)

		mp.set_property_native("vf", vf)
		if @startTime > -1 and @endTime > -1
			mp.set_property_native("ab-loop-a", @startTime)
			mp.set_property_native("ab-loop-b", @endTime)
			mp.set_property_native("time-pos", @startTime)
		mp.set_property_native("pause", false)

	dispose: =>
		mp.set_property("ab-loop-a", "no")
		mp.set_property("ab-loop-b", "no")
		
		-- restore original properties
		for prop, value in pairs @originalProperties
			mp.set_property_native(prop, value)

	draw: =>
		window_w, window_h = mp.get_osd_size()
		ass = assdraw.ass_new()
		ass\new_event()
		self\setup_text(ass)
		ass\append("Press #{bold('ESC')} to exit preview.\\N")
		mp.set_osd_ass(window_w, window_h, ass.text)

	cancel: =>
		self\hide!
		self.callback()
