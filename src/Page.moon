class Page
	add_keybinds: =>
		if not @keybinds
			return
		for key, func in pairs @keybinds
			mp.add_forced_key_binding(key, key, func, {repeatable: true})

	remove_keybinds: =>
		if not @keybinds
			return
		for key, _ in pairs @keybinds
			mp.remove_key_binding(key)

	observe_properties: =>
		-- We can't just pass the self\draw! function as it's resolved to a closure 
		-- internally, and closures can't be unobserved.
		@sizeCallback = () ->
			self\draw!
		-- This is the same list of properties used in CropPage. It might be a good idea to somehow
		-- unite those observers.
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
		for p in *properties
			mp.observe_property(p, "native", @sizeCallback)

	unobserve_properties: =>
		if @sizeCallback
			mp.unobserve_property(@sizeCallback)
			@sizeCallback = nil

	clear: =>
		window_w, window_h = mp.get_osd_size()
		mp.set_osd_ass(window_w, window_h, "")
		mp.osd_message("", 0)

	prepare: =>
		nil

	dispose: =>
		nil

	show: =>
		@visible = true
		self\observe_properties!
		self\add_keybinds!
		self\prepare!
		self\clear!
		self\draw!

	hide: =>
		@visible = false
		self\unobserve_properties!
		self\remove_keybinds!
		self\clear!
		self\dispose!

	setup_text: (ass) =>
		scale = calculate_scale_factor!
		margin = options.margin * scale
		ass\pos(margin, margin)
		ass\append("{\\fs#{options.font_size * scale}}")
