monitor_dimensions!
mainPage = MainPage!
mp.add_key_binding(options.keybind, "display-webm-encoder", mainPage\show, {repeatable: false})
mp.register_event("file-loaded", mainPage\setupStartAndEndTimes)