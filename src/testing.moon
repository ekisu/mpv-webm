emit_event = (event_name, ...) ->
    mp.commandv("script-message", "webm-#{event_name}", ...)

test_set_options = (new_options_json) ->
    new_options = utils.parse_json(new_options_json)

    for k, v in pairs new_options
        options[k] = v

mp.register_script_message("mpv-webm-set-options", test_set_options)
