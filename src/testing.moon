emit_event = (event_name) ->
    mp.commandv("script-message", "webm-#{event_name}")
