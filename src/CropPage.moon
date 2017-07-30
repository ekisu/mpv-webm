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
