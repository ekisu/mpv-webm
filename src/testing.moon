emit_event = (event_name, ...) ->
    mp.commandv("script-message", "webm-#{event_name}", ...)

test_set_options = (new_options_json) ->
    new_options = utils.parse_json(new_options_json)

    for k, v in pairs new_options
        options[k] = v
    emit_event("options-set")

mp.register_script_message("mpv-webm-set-options", test_set_options)

-- Register after MainPage is constructed so tests use the same controller
-- and encoding path as the interactive UI, without loading alternate code.
register_test_handlers = (main_page) ->
    mp.register_script_message("mpv-webm-set-range", (range_json) ->
        range = utils.parse_json(range_json)
        main_page.startTime = range.startTime
        main_page.endTime = range.endTime
        if range.region
            for key in *{"x", "y", "w", "h"}
                main_page.region[key] = range.region[key]
        emit_event("range-set")
    )
    mp.register_script_message("mpv-webm-encode", -> main_page\encode!)
    mp.register_script_message("mpv-webm-get-state", ->
        mouse_x, mouse_y = mp.get_mouse_pos!
        osd_w, osd_h = mp.get_osd_size!
        state_json = utils.format_json({
            startTime: main_page.startTime
            endTime: main_page.endTime
            region: {x: main_page.region.x, y: main_page.region.y, w: main_page.region.w, h: main_page.region.h}
            mainVisible: main_page.visible or false
            mouse: {x: mouse_x, y: mouse_y}
            osd: {w: osd_w, h: osd_h}
        })
        emit_event("state", state_json)
    )
