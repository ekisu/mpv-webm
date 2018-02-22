-- Represents a video/audio/subtitle track.
class Track
	new: (id, index, type) =>
		@id = id
		@index = index
		@type = type

-- Represents an mpv video/audio filter.
class MpvFilter
	new: (name, params={}) =>
		-- Note: You don't need to specify the lavfi- prefix to
		-- use valid lavfi filters, it's only used as a disambiguation
		-- against mpv's builtin filters. So not all compatible filters
		-- will be caught here.
		if string.sub(name,1,6)=="lavfi-" then
			@name = string.sub(name,7,string.len(name))
			@lavfiCompat = true
		else
			@name = name
			@lavfiCompat = false
		@params = params

class EncodingParameters
	new: =>
		-- {Format}
		-- The format to encode in.
		@format = nil

		-- {string}
		-- The full path to the input stream.
		@inputPath = nil

		-- {string}
		-- The output path the encoding will be written to.
		@outputPath = nil

		-- {number}
		-- The start time in milliseconds.
		@startTime = 0

		-- {number}
		-- The end time in milliseconds.
		@endTime = 0

		-- {Region}
		-- A region specifying how to crop the video. `nil`
		-- for no cropping.
		@crop = nil

		-- {Point}
		-- A point specifying how the video should be
		-- scaled. `nil` means no scaling and `-1` for
		-- either x or y means aspect ratio should be
		-- maintained.
		@scale = nil

		-- {Track}
		-- The video track to include. `nil` for no video.
		@videoTrack = nil

		-- {Track}
		-- The audio track to include. `nil` for no audio.
		@audioTrack = nil

		-- {Track}
		-- The subtitle track to include. `nil` for no
		-- subtitles.
		@subTrack = nil

		-- {number}
		-- The target bitrate in kB. `0` to disable.
		@bitrate = 0

		-- {number}
		-- The minimum allowed bitrate in kB. `0` to
		-- disable.
		@minBitrate = 0

		-- {number}
		-- The maximum allowed bitrate in kB. `0` to
		-- disable.
		@maxBitrate = 0

		-- {number}
		-- The target audio bitrate in kB. `0` to disable.
		@audioBitrate = 0

		-- {boolean}
		-- Whether or not to use two-pass encoding.
		@twopass = false

		-- {MpvFilter[]}
		-- A table of additional mpv filters that should be
		-- applied to the encoding, or attempted to.
		@mpvFilters = {}

		-- {Table}
		-- Additional (backend-specific) flags.
		@flags = {}
