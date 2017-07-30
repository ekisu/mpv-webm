class Page
	add_keybinds: =>
		for key, func in pairs @keybinds
			mp.add_forced_key_binding(key, key, func, {repeatable: true})

	remove_keybinds: =>
		for key, _ in pairs @keybinds
			mp.remove_key_binding(key)

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
		self\add_keybinds!
		self\prepare!
		self\clear!
		self\draw!

	hide: =>
		@visible = false
		self\remove_keybinds!
		self\clear!
		self\dispose!

	setup_text: (ass) =>
		ass\pos(options.margin, options.margin)
		ass\append("{\\fs#{options.font_size}}")
