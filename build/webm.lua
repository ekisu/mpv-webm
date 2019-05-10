local mp = require("mp")
local assdraw = require("mp.assdraw")
local msg = require("mp.msg")
local utils = require("mp.utils")
local mpopts = require("mp.options")
local options = {
  -- Defaults to shift+w
  keybind = "W",
  -- If empty, saves on the same directory of the playing video.
  -- A starting "~" will be replaced by the home dir.
  output_directory = "",
  run_detached = false,
  -- Template string for the output file
  -- %f - Filename, with extension
  -- %F - Filename, without extension
  -- %T - Media title, if it exists, or filename, with extension (useful for some streams, such as YouTube).
  -- %s, %e - Start and end time, with milliseconds
  -- %S, %E - Start and time, without milliseconds
  -- %M - "-audio", if audio is enabled, empty otherwise
  output_template = "%F-[%s-%e]%M",
  -- Scale video to a certain height, keeping the aspect ratio. -1 disables it.
  scale_height = -1,
  -- Target filesize, in kB.
  target_filesize = 2500,
  -- If true, will use stricter flags to ensure the resulting file doesn't
  -- overshoot the target filesize. Not recommended, as constrained quality
  -- mode should work well, unless you're really having trouble hitting
  -- the target size.
  strict_filesize_constraint = false,
  strict_bitrate_multiplier = 0.95,
  -- In kilobits.
  strict_audio_bitrate = 64,
  -- Sets the output format, from a few predefined ones.
  -- Currently we have webm-vp8 (libvpx/libvorbis), webm-vp9 (libvpx-vp9/libvorbis),
  -- mp4 (libh264/aac) and raw (rawvideo/pcm_s16le).
  output_format = "webm-vp8",
  -- The encoding backend to use. Currently supports mpv and ffmpeg.
  backend = "mpv",
  -- Location to the backend executable. Leave blank to have this fall back on the backend option.
  backend_location = "",
  twopass = false,
  -- If set, applies the video filters currently used on the playback to the encode.
  apply_current_filters = true,
  -- Set the number of encoding threads, for codecs libvpx and libvpx-vp9
  libvpx_threads = 4,
  additional_flags = "",
  -- Useful for flags that may impact output filesize, such as crf, qmin, qmax etc
  -- Won't be applied when strict_filesize_constraint is on.
  non_strict_additional_flags = "--ovcopts-add=crf=10",
  -- The font size used in the menu. Isn't used for the notifications (started encode, finished encode etc)
  font_size = 28,
  margin = 10,
  message_duration = 5
}
mpopts.read_options(options)
local bold
bold = function(text)
  return "{\\b1}" .. tostring(text) .. "{\\b0}"
end
local message
message = function(text, duration)
  local ass = mp.get_property_osd("osd-ass-cc/0")
  ass = ass .. text
  return mp.osd_message(ass, duration or options.message_duration)
end
local append
append = function(a, b)
  for _, val in ipairs(b) do
    a[#a + 1] = val
  end
  return a
end
local seconds_to_time_string
seconds_to_time_string = function(seconds, no_ms, full)
  if seconds < 0 then
    return "unknown"
  end
  local ret = ""
  if not (no_ms) then
    ret = string.format(".%03d", seconds * 1000 % 1000)
  end
  ret = string.format("%02d:%02d%s", math.floor(seconds / 60) % 60, math.floor(seconds) % 60, ret)
  if full or seconds > 3600 then
    ret = string.format("%d:%s", math.floor(seconds / 3600), ret)
  end
  return ret
end
local seconds_to_path_element
seconds_to_path_element = function(seconds, no_ms, full)
  local time_string = seconds_to_time_string(seconds, no_ms, full)
  local _
  time_string, _ = time_string:gsub(":", ".")
  return time_string
end
local file_exists
file_exists = function(name)
  local f = io.open(name, "r")
  if f ~= nil then
    io.close(f)
    return true
  end
  return false
end
local format_filename
format_filename = function(startTime, endTime, videoFormat)
  local replaceTable = {
    ["%%f"] = mp.get_property("filename"),
    ["%%F"] = mp.get_property("filename/no-ext"),
    ["%%s"] = seconds_to_path_element(startTime),
    ["%%S"] = seconds_to_path_element(startTime, true),
    ["%%e"] = seconds_to_path_element(endTime),
    ["%%E"] = seconds_to_path_element(endTime, true),
    ["%%T"] = mp.get_property("media-title"),
    ["%%M"] = (mp.get_property_native('aid') and not mp.get_property_native('mute')) and '-audio' or ''
  }
  local filename = options.output_template
  for format, value in pairs(replaceTable) do
    local _
    filename, _ = filename:gsub(format, value)
  end
  local _
  filename, _ = filename:gsub("[<>:\"/\\|?*]", "")
  return tostring(filename) .. "." .. tostring(videoFormat.outputExtension)
end
local parse_directory
parse_directory = function(dir)
  local home_dir = os.getenv("HOME")
  if not home_dir then
    home_dir = os.getenv("USERPROFILE")
  end
  if not home_dir then
    local drive = os.getenv("HOMEDRIVE")
    local path = os.getenv("HOMEPATH")
    if drive and path then
      home_dir = utils.join_path(drive, path)
    else
      msg.warn("Couldn't find home dir.")
      home_dir = ""
    end
  end
  local _
  dir, _ = dir:gsub("^~", home_dir)
  return dir
end
local get_null_path
get_null_path = function()
  if file_exists("/dev/null") then
    return "/dev/null"
  end
  return "NUL"
end
local run_subprocess
run_subprocess = function(params)
  local res = utils.subprocess(params)
  if res.status ~= 0 then
    msg.verbose("Command failed! Reason: ", res.error, " Killed by us? ", res.killed_by_us and "yes" or "no")
    msg.verbose("Command stdout: ")
    msg.verbose(res.stdout)
    return false
  end
  return true
end
local calculate_scale_factor
calculate_scale_factor = function()
  local baseResY = 720
  local osd_w, osd_h = mp.get_osd_size()
  return osd_h / baseResY
end
local get_backend_location
get_backend_location = function()
  if not options.backend_location or string.len(options.backend_location) == 0 then
    return options.backend
  end
  return options.backend_location
end
local dimensions_changed = true
local _video_dimensions = { }
local get_video_dimensions
get_video_dimensions = function()
  if not (dimensions_changed) then
    return _video_dimensions
  end
  local video_params = mp.get_property_native("video-out-params")
  if not video_params then
    return nil
  end
  dimensions_changed = false
  local keep_aspect = mp.get_property_bool("keepaspect")
  local w = video_params["w"]
  local h = video_params["h"]
  local dw = video_params["dw"]
  local dh = video_params["dh"]
  if mp.get_property_number("video-rotate") % 180 == 90 then
    w, h = h, w
    dw, dh = dh, dw
  end
  _video_dimensions = {
    top_left = { },
    bottom_right = { },
    ratios = { }
  }
  local window_w, window_h = mp.get_osd_size()
  if keep_aspect then
    local unscaled = mp.get_property_native("video-unscaled")
    local panscan = mp.get_property_number("panscan")
    local fwidth = window_w
    local fheight = math.floor(window_w / dw * dh)
    if fheight > window_h or fheight < h then
      local tmpw = math.floor(window_h / dh * dw)
      if tmpw <= window_w then
        fheight = window_h
        fwidth = tmpw
      end
    end
    local vo_panscan_area = window_h - fheight
    local f_w = fwidth / fheight
    local f_h = 1
    if vo_panscan_area == 0 then
      vo_panscan_area = window_h - fwidth
      f_w = 1
      f_h = fheight / fwidth
    end
    if unscaled or unscaled == "downscale-big" then
      vo_panscan_area = 0
      if unscaled or (dw <= window_w and dh <= window_h) then
        fwidth = dw
        fheight = dh
      end
    end
    local scaled_width = fwidth + math.floor(vo_panscan_area * panscan * f_w)
    local scaled_height = fheight + math.floor(vo_panscan_area * panscan * f_h)
    local split_scaling
    split_scaling = function(dst_size, scaled_src_size, zoom, align, pan)
      scaled_src_size = math.floor(scaled_src_size * 2 ^ zoom)
      align = (align + 1) / 2
      local dst_start = math.floor((dst_size - scaled_src_size) * align + pan * scaled_src_size)
      if dst_start < 0 then
        dst_start = dst_start + 1
      end
      local dst_end = dst_start + scaled_src_size
      if dst_start >= dst_end then
        dst_start = 0
        dst_end = 1
      end
      return dst_start, dst_end
    end
    local zoom = mp.get_property_number("video-zoom")
    local align_x = mp.get_property_number("video-align-x")
    local pan_x = mp.get_property_number("video-pan-x")
    _video_dimensions.top_left.x, _video_dimensions.bottom_right.x = split_scaling(window_w, scaled_width, zoom, align_x, pan_x)
    local align_y = mp.get_property_number("video-align-y")
    local pan_y = mp.get_property_number("video-pan-y")
    _video_dimensions.top_left.y, _video_dimensions.bottom_right.y = split_scaling(window_h, scaled_height, zoom, align_y, pan_y)
  else
    _video_dimensions.top_left.x = 0
    _video_dimensions.bottom_right.x = window_w
    _video_dimensions.top_left.y = 0
    _video_dimensions.bottom_right.y = window_h
  end
  _video_dimensions.ratios.w = w / (_video_dimensions.bottom_right.x - _video_dimensions.top_left.x)
  _video_dimensions.ratios.h = h / (_video_dimensions.bottom_right.y - _video_dimensions.top_left.y)
  return _video_dimensions
end
local set_dimensions_changed
set_dimensions_changed = function()
  dimensions_changed = true
end
local monitor_dimensions
monitor_dimensions = function()
  local properties = {
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
    "osd-height"
  }
  for _, p in ipairs(properties) do
    mp.observe_property(p, "native", set_dimensions_changed)
  end
end
local clamp
clamp = function(min, val, max)
  if val <= min then
    return min
  end
  if val >= max then
    return max
  end
  return val
end
local clamp_point
clamp_point = function(top_left, point, bottom_right)
  return {
    x = clamp(top_left.x, point.x, bottom_right.x),
    y = clamp(top_left.y, point.y, bottom_right.y)
  }
end
local Point
do
  local _class_0
  local _base_0 = { }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, x, y)
      if x == nil then
        x = -1
      end
      if y == nil then
        y = -1
      end
      self.x = x
      self.y = y
    end,
    __base = _base_0,
    __name = "Point"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Point = _class_0
end
local VideoPoint
do
  local _class_0
  local _parent_0 = Point
  local _base_0 = {
    set_from_screen = function(self, sx, sy)
      local d = get_video_dimensions()
      local point = clamp_point(d.top_left, {
        x = sx,
        y = sy
      }, d.bottom_right)
      self.x = math.floor(d.ratios.w * (point.x - d.top_left.x) + 0.5)
      self.y = math.floor(d.ratios.h * (point.y - d.top_left.y) + 0.5)
    end,
    to_screen = function(self)
      local d = get_video_dimensions()
      return {
        x = math.floor(self.x / d.ratios.w + d.top_left.x + 0.5),
        y = math.floor(self.y / d.ratios.h + d.top_left.y + 0.5)
      }
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, ...)
      return _class_0.__parent.__init(self, ...)
    end,
    __base = _base_0,
    __name = "VideoPoint",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  VideoPoint = _class_0
end
local Region
do
  local _class_0
  local _base_0 = {
    is_valid = function(self)
      return self.x > -1 and self.y > -1 and self.w > -1 and self.h > -1
    end,
    set_from_points = function(self, p1, p2)
      self.x = math.min(p1.x, p2.x)
      self.y = math.min(p1.y, p2.y)
      self.w = math.abs(p1.x - p2.x)
      self.h = math.abs(p1.y - p2.y)
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.x = -1
      self.y = -1
      self.w = -1
      self.h = -1
    end,
    __base = _base_0,
    __name = "Region"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Region = _class_0
end
local make_fullscreen_region
make_fullscreen_region = function()
  local r = Region()
  local d = get_video_dimensions()
  local a = VideoPoint()
  local b = VideoPoint()
  local xa, ya
  do
    local _obj_0 = d.top_left
    xa, ya = _obj_0.x, _obj_0.y
  end
  a:set_from_screen(xa, ya)
  local xb, yb
  do
    local _obj_0 = d.bottom_right
    xb, yb = _obj_0.x, _obj_0.y
  end
  b:set_from_screen(xb, yb)
  r:set_from_points(a, b)
  return r
end
local Track
do
  local _class_0
  local _base_0 = { }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, id, index, type, data)
      self.id = id
      self.index = index
      self.type = type
      self.data = data
    end,
    __base = _base_0,
    __name = "Track"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Track = _class_0
end
local MpvFilter
do
  local _class_0
  local _base_0 = { }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, name, params)
      if params == nil then
        params = { }
      end
      self.lavfiCompat = not self.__class.isBuiltin(name)
      if string.sub(name, 1, 6) == "lavfi-" then
        self.name = string.sub(name, 7, string.len(name))
      else
        self.name = name
      end
      self.params = params
    end,
    __base = _base_0,
    __name = "MpvFilter"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  self.isBuiltin = function(name)
    return (name == "format" or name == "sub" or name == "convert" or name == "d3d11vpp" or name == "lavcac3enc" or name == "lavrresample" or name == "rubberband" or name == "scaletempo")
  end
  MpvFilter = _class_0
end
local EncodingParameters
do
  local _class_0
  local _base_0 = { }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.format = nil
      self.inputPath = nil
      self.outputPath = nil
      self.startTime = 0
      self.endTime = 0
      self.crop = nil
      self.scale = nil
      self.videoTrack = nil
      self.audioTrack = nil
      self.subTrack = nil
      self.bitrate = 0
      self.minBitrate = 0
      self.maxBitrate = 0
      self.audioBitrate = 0
      self.twopass = false
      self.mpvFilters = { }
      self.flags = { }
    end,
    __base = _base_0,
    __name = "EncodingParameters"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  EncodingParameters = _class_0
end
local formats = { }
local Format
do
  local _class_0
  local _base_0 = {
    getPreFilters = function(self, backend)
      return { }
    end,
    getPostFilters = function(self, backend)
      return { }
    end,
    getFlags = function(self, backend)
      return { }
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.displayName = "Basic"
      self.supportsTwopass = true
      self.videoCodec = ""
      self.audioCodec = ""
      self.outputExtension = ""
      self.acceptsBitrate = true
    end,
    __base = _base_0,
    __name = "Format"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Format = _class_0
end
local RawVideo
do
  local _class_0
  local _parent_0 = Format
  local _base_0 = {
    getColorspace = function(self)
      local csp = mp.get_property("colormatrix")
      local _exp_0 = csp
      if "bt.601" == _exp_0 then
        return "bt601"
      elseif "bt.709" == _exp_0 then
        return "bt709"
      elseif "bt.2020" == _exp_0 then
        return "bt2020"
      elseif "smpte-240m" == _exp_0 then
        return "smpte240m"
      else
        msg.info("Warning, unknown colorspace " .. tostring(csp) .. " detected, using bt.601.")
        return "bt601"
      end
    end,
    getPostFilters = function(self, backend)
      return {
        MpvFilter("lavfi-format", {
          ["pix_fmts"] = "yuv444p16"
        }),
        MpvFilter("lavfi-scale", {
          ["in_color_matrix"] = self:getColorspace()
        }),
        MpvFilter("lavfi-format", {
          ["pix_fmts"] = "bgr24"
        })
      }
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self)
      self.displayName = "Raw"
      self.supportsTwopass = false
      self.videoCodec = "rawvideo"
      self.audioCodec = "pcm_s16le"
      self.outputExtension = "avi"
      self.acceptsBitrate = false
    end,
    __base = _base_0,
    __name = "RawVideo",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  RawVideo = _class_0
end
formats["raw"] = RawVideo()
local WebmVP8
do
  local _class_0
  local _parent_0 = Format
  local _base_0 = {
    getPreFilters = function(self, backend)
      local colormatrixFilter = {
        ["bt.709"] = "bt709",
        ["bt.2020"] = "bt2020",
        ["smpte-240m"] = "smpte240m"
      }
      local ret = { }
      local colormatrix = mp.get_property_native("video-params/colormatrix")
      if colormatrixFilter[colormatrix] then
        append(ret, {
          MpvFilter("lavfi-colormatrix", {
            ["src"] = colormatrixFilter[colormatrix],
            ["dst"] = "bt601"
          })
        })
      end
      return ret
    end,
    getFlags = function(self, backend)
      local _exp_0 = backend.name
      if "mpv" == _exp_0 then
        return {
          "--ovcopts-add=threads=" .. tostring(options.libvpx_threads)
        }
      elseif "ffmpeg" == _exp_0 then
        return {
          "-threads",
          options.libvpx_threads
        }
      end
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self)
      self.displayName = "WebM"
      self.supportsTwopass = true
      self.videoCodec = "libvpx"
      self.audioCodec = "libvorbis"
      self.outputExtension = "webm"
      self.acceptsBitrate = true
    end,
    __base = _base_0,
    __name = "WebmVP8",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  WebmVP8 = _class_0
end
formats["webm-vp8"] = WebmVP8()
local WebmVP9
do
  local _class_0
  local _parent_0 = Format
  local _base_0 = {
    getFlags = function(self, backend)
      local _exp_0 = backend.name
      if "mpv" == _exp_0 then
        return {
          "--ovcopts-add=threads=" .. tostring(options.libvpx_threads)
        }
      elseif "ffmpeg" == _exp_0 then
        return {
          "-threads",
          options.libvpx_threads
        }
      end
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self)
      self.displayName = "WebM (VP9)"
      self.supportsTwopass = true
      self.videoCodec = "libvpx-vp9"
      self.audioCodec = "libvorbis"
      self.outputExtension = "webm"
      self.acceptsBitrate = true
    end,
    __base = _base_0,
    __name = "WebmVP9",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  WebmVP9 = _class_0
end
formats["webm-vp9"] = WebmVP9()
local MP4
do
  local _class_0
  local _parent_0 = Format
  local _base_0 = { }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self)
      self.displayName = "MP4 (h264/AAC)"
      self.supportsTwopass = true
      self.videoCodec = "libx264"
      self.audioCodec = "aac"
      self.outputExtension = "mp4"
      self.acceptsBitrate = true
    end,
    __base = _base_0,
    __name = "MP4",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  MP4 = _class_0
end
formats["mp4"] = MP4()
local backends = { }
local Backend
do
  local _class_0
  local _base_0 = {
    encode = function(self, params, detached)
      msg.verbose("Building command from params: ", utils.to_string(params))
      local command = self:buildCommand(params)
      if command then
        msg.info("Encoding to", params.outputPath)
        msg.verbose("Command line:", table.concat(command, " "))
        if detached then
          utils.subprocess_detached({
            args = command
          })
          return true
        end
        return run_subprocess({
          args = command,
          cancellable = false
        })
      end
      return false
    end,
    buildCommand = function(self, params)
      return nil
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.name = "No backend"
    end,
    __base = _base_0,
    __name = "Backend"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Backend = _class_0
end
local MpvBackend
do
  local _class_0
  local _parent_0 = Backend
  local _base_0 = {
    appendProperty = function(self, out, property_name, option_name)
      option_name = option_name or property_name
      local prop = mp.get_property(property_name)
      if prop and prop ~= "" then
        return append(out, {
          "--" .. tostring(option_name) .. "=" .. tostring(prop)
        })
      end
    end,
    getPlaybackOptions = function(self)
      local ret = { }
      self:appendProperty(ret, "sub-ass-override")
      self:appendProperty(ret, "sub-ass-force-style")
      self:appendProperty(ret, "sub-auto")
      for _, track in ipairs(mp.get_property_native("track-list")) do
        if track["type"] == "sub" and track["external"] then
          append(ret, {
            "--sub-files-append=" .. tostring(track['external-filename'])
          })
        end
      end
      return ret
    end,
    solveFilters = function(self, filters)
      local solved = { }
      for _index_0 = 1, #filters do
        local filter = filters[_index_0]
        local str = filter.lavfiCompat and "lavfi-" or ""
        str = str .. (filter.name .. "=")
        for k, v in pairs(filter.params) do
          str = str .. tostring(k) .. "=%" .. tostring(string.len(v)) .. "%" .. tostring(v) .. ":"
        end
        solved[#solved + 1] = string.sub(str, 0, string.len(str) - 1)
      end
      return solved
    end,
    buildCommand = function(self, params)
      local format = params.format
      local command = {
        get_backend_location(),
        params.inputPath,
        "--start=" .. seconds_to_time_string(params.startTime, false, true),
        "--end=" .. seconds_to_time_string(params.endTime, false, true),
        "--ovc=" .. tostring(format.videoCodec),
        "--oac=" .. tostring(format.audioCodec),
        "--loop-file=no"
      }
      append(command, {
        "--vid=" .. (params.videoTrack ~= nil and tostring(params.videoTrack.id) or "no"),
        "--aid=" .. (params.audioTrack ~= nil and tostring(params.audioTrack.id) or "no"),
        "--sid=" .. (params.subTrack ~= nil and tostring(params.subTrack.id) or "no")
      })
      append(command, self:getPlaybackOptions())
      local filters = { }
      append(filters, self:solveFilters(format:getPreFilters(self)))
      append(filters, self:solveFilters(params.mpvFilters))
      if params.crop then
        filters[#filters + 1] = "lavfi-crop=" .. tostring(params.crop.w) .. ":" .. tostring(params.crop.h) .. ":" .. tostring(params.crop.x) .. ":" .. tostring(params.crop.y)
      end
      if params.scale then
        filters[#filters + 1] = "lavfi-scale=" .. tostring(params.scale.x) .. ":" .. tostring(params.scale.y)
      end
      append(filters, self:solveFilters(format:getPostFilters(self)))
      for _index_0 = 1, #filters do
        local f = filters[_index_0]
        command[#command + 1] = "--vf-add=" .. tostring(f)
      end
      append(command, format:getFlags(self))
      if format.acceptsBitrate then
        if params.audioBitrate ~= 0 then
          command[#command + 1] = "--oacopts-add=b=" .. tostring(params.audioBitrate) .. "k"
        end
        if params.bitrate ~= 0 then
          command[#command + 1] = "--ovcopts-add=b=" .. tostring(params.bitrate) .. "k"
        end
        if params.minBitrate ~= 0 then
          command[#command + 1] = "--ovcopts-add=minrate=" .. tostring(params.bitrate) .. "k"
        end
        if params.maxBitrate ~= 0 then
          command[#command + 1] = "--ovcopts-add=maxrate=" .. tostring(params.bitrate) .. "k"
        end
      end
      local _list_0 = params.flags
      for _index_0 = 1, #_list_0 do
        local flag = _list_0[_index_0]
        command[#command + 1] = flag
      end
      if params.twopass and format.supportsTwopass then
        local first_pass_cmdline
        do
          local _accum_0 = { }
          local _len_0 = 1
          for _index_0 = 1, #command do
            local arg = command[_index_0]
            _accum_0[_len_0] = arg
            _len_0 = _len_0 + 1
          end
          first_pass_cmdline = _accum_0
        end
        append(first_pass_cmdline, {
          "--ovcopts-add=flags=+pass1",
          "-of=" .. tostring(format.outputExtension),
          "-o=" .. tostring(get_null_path())
        })
        message("Starting first pass...")
        msg.verbose("First-pass command line: ", table.concat(first_pass_cmdline, " "))
        local res = run_subprocess({
          args = first_pass_cmdline,
          cancellable = false
        })
        if not res then
          message("First pass failed! Check the logs for details.")
          return nil
        end
        append(command, {
          "--ovcopts-add=flags=+pass2"
        })
      end
      append(command, {
        "-o=" .. tostring(params.outputPath)
      })
      return command
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self)
      self.name = "mpv"
    end,
    __base = _base_0,
    __name = "MpvBackend",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  MpvBackend = _class_0
end
backends["mpv"] = MpvBackend()
local FfmpegBackend
do
  local _class_0
  local _parent_0 = Backend
  local _base_0 = {
    solveFilters = function(self, filters)
      local solved = { }
      for _index_0 = 1, #filters do
        local _continue_0 = false
        repeat
          local filter = filters[_index_0]
          if not filter.lavfiCompat then
            _continue_0 = true
            break
          end
          local str = filter.name .. "="
          local ordered_params = { }
          local highest_n = 0
          for k, v in pairs(filter.params) do
            local param_n = tonumber(string.match(k, "^@(%d+)$"))
            if param_n ~= nil then
              ordered_params[param_n] = v
              if param_n > highest_n then
                highest_n = param_n
              end
            else
              str = str .. tostring(k) .. "=" .. tostring(v) .. ":"
            end
          end
          for i = 0, highest_n do
            if ordered_params[i] ~= nil then
              str = str .. tostring(ordered_params[i]) .. ":"
            end
          end
          solved[#solved + 1] = string.sub(str, 0, string.len(str) - 1)
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return solved
    end,
    escapeFilterParameter = function(self, parameter)
      parameter = parameter:gsub("([\\:'])", "\\%1")
      parameter = parameter:gsub("([\\'%[%],;])", "\\%1")
      return parameter
    end,
    getHardsubFilters = function(self, params)
      if not params.subTrack then
        return { }
      end
      local out = "subtitles="
      local subFile = ""
      local subId = nil
      if params.subTrack.data["external"] then
        subFile = params.subTrack.data["external-filename"]
      else
        subFile = params.inputPath
        subId = params.subTrack.id - 1
      end
      out = out .. ("f=" .. self:escapeFilterParameter(subFile))
      if subIndex ~= nil then
        out = out .. ":si=" .. tostring(subId)
      end
      local subOverride = mp.get_property("sub-ass-override")
      local subForceStyle = mp.get_property("sub-ass-force-style")
      if subOverride ~= "no" and subForceStyle ~= "" then
        out = out .. (":force_style=" .. self:escapeFilterParameter(subForceStyle))
      end
      return {
        out
      }
    end,
    buildCommand = function(self, params)
      local format = params.format
      local command = {
        get_backend_location(),
        "-y",
        "-i",
        params.inputPath,
        "-ss",
        seconds_to_time_string(params.startTime, false, true),
        "-t",
        tostring(params.endTime - params.startTime)
      }
      if params.videoTrack ~= nil and params.videoTrack.index ~= nil then
        append(command, {
          "-map",
          "0:" .. tostring(params.videoTrack.index)
        })
      end
      if params.audioTrack ~= nil and params.audioTrack.index ~= nil then
        append(command, {
          "-map",
          "0:" .. tostring(params.audioTrack.index)
        })
      end
      append(command, {
        "-c:v",
        tostring(format.videoCodec),
        "-c:a",
        tostring(format.audioCodec)
      })
      local filters = { }
      append(filters, self:solveFilters(format:getPreFilters(self)))
      append(filters, self:solveFilters(params.mpvFilters))
      if params.crop then
        filters[#filters + 1] = "crop=" .. tostring(params.crop.w) .. ":" .. tostring(params.crop.h) .. ":" .. tostring(params.crop.x) .. ":" .. tostring(params.crop.y)
      end
      if params.scale then
        filters[#filters + 1] = "scale=" .. tostring(params.scale.x) .. ":" .. tostring(params.scale.y)
      end
      append(filters, self:getHardsubFilters(params))
      append(filters, self:solveFilters(format:getPostFilters(self)))
      append(command, {
        "-vf",
        table.concat(filters, ",")
      })
      append(command, format:getFlags(self))
      if format.acceptsBitrate then
        if params.audioBitrate ~= 0 then
          append(command, {
            "-b:a",
            tostring(params.audioBitrate) .. "K"
          })
        end
        if params.bitrate ~= 0 then
          append(command, {
            "-b:v",
            tostring(params.bitrate) .. "K"
          })
        end
        if params.minBitrate ~= 0 then
          append(command, {
            "-minrate",
            tostring(params.minBitrate) .. "K"
          })
        end
        if params.maxBitrate ~= 0 then
          append(command, {
            "-maxrate",
            tostring(params.maxBitrate) .. "K"
          })
        end
      end
      local _list_0 = params.flags
      for _index_0 = 1, #_list_0 do
        local flag = _list_0[_index_0]
        command[#command + 1] = flag
      end
      if params.twopass and format.supportsTwopass then
        local first_pass_cmdline
        do
          local _accum_0 = { }
          local _len_0 = 1
          for _index_0 = 1, #command do
            local arg = command[_index_0]
            _accum_0[_len_0] = arg
            _len_0 = _len_0 + 1
          end
          first_pass_cmdline = _accum_0
        end
        append(first_pass_cmdline, {
          "-pass",
          "1",
          "-f",
          format.outputExtension,
          get_null_path()
        })
        message("Starting first pass...")
        msg.verbose("First-pass command line: ", table.concat(first_pass_cmdline, " "))
        local res = run_subprocess({
          args = first_pass_cmdline,
          cancellable = false
        })
        if not res then
          message("First pass failed! Check the logs for details.")
          return nil
        end
        append(command, {
          "-pass",
          "2"
        })
      end
      append(command, {
        params.outputPath
      })
      return command
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self)
      self.name = "ffmpeg"
    end,
    __base = _base_0,
    __name = "FfmpegBackend",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  FfmpegBackend = _class_0
end
backends["ffmpeg"] = FfmpegBackend()
local get_active_tracks
get_active_tracks = function()
  local accepted = {
    video = true,
    audio = not mp.get_property_bool("mute"),
    sub = mp.get_property_bool("sub-visibility")
  }
  local active = { }
  for _, track in ipairs(mp.get_property_native("track-list")) do
    if track["selected"] and accepted[track["type"]] then
      active[#active + 1] = Track(track["id"], track["ff-index"], track["type"], track)
    end
  end
  return active
end
local get_current_filters
get_current_filters = function()
  local current_filters = mp.get_property_native("vf")
  local filters = { }
  msg.verbose("apply_current_filters: got " .. tostring(#current_filters) .. " currently applied.")
  for _index_0 = 1, #current_filters do
    local _continue_0 = false
    repeat
      local filter = current_filters[_index_0]
      msg.verbose("apply_current_filters: filter name: " .. tostring(filter['name']))
      if filter.enabled == false then
        _continue_0 = true
        break
      end
      if filter.name == "crop" then
        _continue_0 = true
        break
      end
      filters[#filters + 1] = MpvFilter(filter.name, filter.params)
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return filters
end
local encode
encode = function(region, startTime, endTime)
  local backend = backends[options.backend]
  local format = formats[options.output_format]
  local params = EncodingParameters()
  params.format = format
  params.startTime = startTime
  params.endTime = endTime
  params.inputPath = mp.get_property("path")
  if not params.inputPath then
    message("No file is being played")
    return 
  end
  for _, track in ipairs(get_active_tracks()) do
    local _exp_0 = track["type"]
    if "video" == _exp_0 then
      params.videoTrack = track
    elseif "audio" == _exp_0 then
      params.audioTrack = track
    elseif "sub" == _exp_0 then
      params.subTrack = track
    end
  end
  if options.scale_height > 0 then
    params.scale = Point(-1, options.scale_height)
  end
  if options.apply_current_filters then
    params.mpvFilters = get_current_filters()
  end
  if not region or not region:is_valid() then
    msg.verbose("Invalid/unset region, using fullscreen one.")
    params.crop = make_fullscreen_region()
  else
    params.crop = region
  end
  if options.target_filesize > 0 then
    local dT = endTime - startTime
    if options.strict_filesize_constraint then
      local video_kilobits = options.target_filesize * 8
      if params.audioTrack ~= nil then
        video_kilobits = video_kilobits - dT * options.strict_audio_bitrate
        params.audioBitrate = options.strict_audio_bitrate
      end
      video_kilobits = video_kilobits * options.strict_bitrate_multiplier
      local bitrate = math.floor(video_kilobits / dT)
      params.bitrate = bitrate
      params.minBitrate = bitrate
      params.maxBitrate = bitrate
    else
      local bitrate = math.floor(options.target_filesize * 8 / dT)
      params.bitrate = bitrate
    end
  end
  for token in string.gmatch(options.additional_flags, "[^%s]+") do
    params.flags[#params.flags + 1] = token
  end
  if not options.strict_filesize_constraint then
    for token in string.gmatch(options.non_strict_additional_flags, "[^%s]+") do
      params.flags[#params.flags + 1] = token
    end
  end
  local is_stream = not file_exists(params.inputPath)
  params.twopass = options.twopass and not is_stream
  local dir = ""
  if options.output_directory ~= "" then
    dir = options.output_directory
  elseif is_stream then
    dir = parse_directory("~")
  else
    local _
    dir, _ = utils.split_path(params.inputPath)
  end
  local formatted_filename = format_filename(startTime, endTime, format)
  local out_path = utils.join_path(dir, formatted_filename)
  params.outputPath = out_path
  if options.run_detached then
    local res = backend:encode(params, true)
    if res then
      return message("Started encode, process was detached. (" .. tostring(backend.name) .. ")")
    else
      return message("Encode failed! Couldn't start encode. Check the logs for details.")
    end
  else
    message("Started encode... (" .. tostring(backend.name) .. ")")
    local res = backend:encode(params, false)
    if res then
      return message("Encoded successfully! Saved to\\N" .. tostring(bold(params.outputPath)))
    else
      return message("Encode failed! Check the logs for details.")
    end
  end
end
local Page
do
  local _class_0
  local _base_0 = {
    add_keybinds = function(self)
      for key, func in pairs(self.keybinds) do
        mp.add_forced_key_binding(key, key, func, {
          repeatable = true
        })
      end
    end,
    remove_keybinds = function(self)
      for key, _ in pairs(self.keybinds) do
        mp.remove_key_binding(key)
      end
    end,
    observe_properties = function(self)
      self.sizeCallback = function()
        return self:draw()
      end
      local properties = {
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
        "osd-height"
      }
      for _index_0 = 1, #properties do
        local p = properties[_index_0]
        mp.observe_property(p, "native", self.sizeCallback)
      end
    end,
    unobserve_properties = function(self)
      if self.sizeCallback then
        mp.unobserve_property(self.sizeCallback)
        self.sizeCallback = nil
      end
    end,
    clear = function(self)
      local window_w, window_h = mp.get_osd_size()
      mp.set_osd_ass(window_w, window_h, "")
      return mp.osd_message("", 0)
    end,
    prepare = function(self)
      return nil
    end,
    dispose = function(self)
      return nil
    end,
    show = function(self)
      self.visible = true
      self:observe_properties()
      self:add_keybinds()
      self:prepare()
      self:clear()
      return self:draw()
    end,
    hide = function(self)
      self.visible = false
      self:unobserve_properties()
      self:remove_keybinds()
      self:clear()
      return self:dispose()
    end,
    setup_text = function(self, ass)
      local scale = calculate_scale_factor()
      local margin = options.margin * scale
      ass:pos(margin, margin)
      return ass:append("{\\fs" .. tostring(options.font_size * scale))
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "Page"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Page = _class_0
end
local CropPage
do
  local _class_0
  local _parent_0 = Page
  local _base_0 = {
    reset = function(self)
      local dimensions = get_video_dimensions()
      local xa, ya
      do
        local _obj_0 = dimensions.top_left
        xa, ya = _obj_0.x, _obj_0.y
      end
      self.pointA:set_from_screen(xa, ya)
      local xb, yb
      do
        local _obj_0 = dimensions.bottom_right
        xb, yb = _obj_0.x, _obj_0.y
      end
      self.pointB:set_from_screen(xb, yb)
      if self.visible then
        return self:draw()
      end
    end,
    setPointA = function(self)
      local posX, posY = mp.get_mouse_pos()
      self.pointA:set_from_screen(posX, posY)
      if self.visible then
        return self:draw()
      end
    end,
    setPointB = function(self)
      local posX, posY = mp.get_mouse_pos()
      self.pointB:set_from_screen(posX, posY)
      if self.visible then
        return self:draw()
      end
    end,
    cancel = function(self)
      self:hide()
      return self.callback(false, nil)
    end,
    finish = function(self)
      local region = Region()
      region:set_from_points(self.pointA, self.pointB)
      self:hide()
      return self.callback(true, region)
    end,
    draw_box = function(self, ass)
      local region = Region()
      region:set_from_points(self.pointA:to_screen(), self.pointB:to_screen())
      local d = get_video_dimensions()
      ass:new_event()
      ass:pos(0, 0)
      ass:append('{\\bord0}')
      ass:append('{\\shad0}')
      ass:append('{\\c&H000000&}')
      ass:append('{\\alpha&H77}')
      ass:draw_start()
      ass:rect_cw(d.top_left.x, d.top_left.y, region.x, region.y + region.h)
      ass:rect_cw(region.x, d.top_left.y, d.bottom_right.x, region.y)
      ass:rect_cw(d.top_left.x, region.y + region.h, region.x + region.w, d.bottom_right.y)
      ass:rect_cw(region.x + region.w, region.y, d.bottom_right.x, d.bottom_right.y)
      return ass:draw_stop()
    end,
    draw = function(self)
      local window = { }
      window.w, window.h = mp.get_osd_size()
      local ass = assdraw.ass_new()
      self:draw_box(ass)
      ass:new_event()
      self:setup_text(ass)
      ass:append(tostring(bold('Crop:')) .. "\\N")
      ass:append(tostring(bold('1:')) .. " change point A (" .. tostring(self.pointA.x) .. ", " .. tostring(self.pointA.y) .. ")\\N")
      ass:append(tostring(bold('2:')) .. " change point B (" .. tostring(self.pointB.x) .. ", " .. tostring(self.pointB.y) .. ")\\N")
      ass:append(tostring(bold('r:')) .. " reset to whole screen\\N")
      ass:append(tostring(bold('ESC:')) .. " cancel crop\\N")
      ass:append(tostring(bold('ENTER:')) .. " confirm crop\\N")
      return mp.set_osd_ass(window.w, window.h, ass.text)
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, callback, region)
      self.pointA = VideoPoint()
      self.pointB = VideoPoint()
      self.keybinds = {
        ["1"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.setPointA
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["2"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.setPointB
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["r"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.reset
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["ESC"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.cancel
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["ENTER"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.finish
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)()
      }
      self:reset()
      self.callback = callback
      if region and region:is_valid() then
        self.pointA.x = region.x
        self.pointA.y = region.y
        self.pointB.x = region.x + region.w
        self.pointB.y = region.y + region.h
      end
    end,
    __base = _base_0,
    __name = "CropPage",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  CropPage = _class_0
end
local Option
do
  local _class_0
  local _base_0 = {
    hasPrevious = function(self)
      local _exp_0 = self.optType
      if "bool" == _exp_0 then
        return true
      elseif "int" == _exp_0 then
        if self.opts.min then
          return self.value > self.opts.min
        else
          return true
        end
      elseif "list" == _exp_0 then
        return self.value > 1
      end
    end,
    hasNext = function(self)
      local _exp_0 = self.optType
      if "bool" == _exp_0 then
        return true
      elseif "int" == _exp_0 then
        if self.opts.max then
          return self.value < self.opts.max
        else
          return true
        end
      elseif "list" == _exp_0 then
        return self.value < #self.opts.possibleValues
      end
    end,
    leftKey = function(self)
      local _exp_0 = self.optType
      if "bool" == _exp_0 then
        self.value = not self.value
      elseif "int" == _exp_0 then
        self.value = self.value - self.opts.step
        if self.opts.min and self.opts.min > self.value then
          self.value = self.opts.min
        end
      elseif "list" == _exp_0 then
        if self.value > 1 then
          self.value = self.value - 1
        end
      end
    end,
    rightKey = function(self)
      local _exp_0 = self.optType
      if "bool" == _exp_0 then
        self.value = not self.value
      elseif "int" == _exp_0 then
        self.value = self.value + self.opts.step
        if self.opts.max and self.opts.max < self.value then
          self.value = self.opts.max
        end
      elseif "list" == _exp_0 then
        if self.value < #self.opts.possibleValues then
          self.value = self.value + 1
        end
      end
    end,
    getValue = function(self)
      local _exp_0 = self.optType
      if "bool" == _exp_0 then
        return self.value
      elseif "int" == _exp_0 then
        return self.value
      elseif "list" == _exp_0 then
        local value, _
        do
          local _obj_0 = self.opts.possibleValues[self.value]
          value, _ = _obj_0[1], _obj_0[2]
        end
        return value
      end
    end,
    setValue = function(self, value)
      local _exp_0 = self.optType
      if "bool" == _exp_0 then
        self.value = value
      elseif "int" == _exp_0 then
        self.value = value
      elseif "list" == _exp_0 then
        local set = false
        for i, possiblePair in ipairs(self.opts.possibleValues) do
          local possibleValue, _
          possibleValue, _ = possiblePair[1], possiblePair[2]
          if possibleValue == value then
            set = true
            self.value = i
            break
          end
        end
        if not set then
          return msg.warn("Tried to set invalid value " .. tostring(value) .. " to " .. tostring(self.displayText) .. " option.")
        end
      end
    end,
    getDisplayValue = function(self)
      local _exp_0 = self.optType
      if "bool" == _exp_0 then
        return self.value and "yes" or "no"
      elseif "int" == _exp_0 then
        if self.opts.altDisplayNames and self.opts.altDisplayNames[self.value] then
          return self.opts.altDisplayNames[self.value]
        else
          return tostring(self.value)
        end
      elseif "list" == _exp_0 then
        local value, displayValue
        do
          local _obj_0 = self.opts.possibleValues[self.value]
          value, displayValue = _obj_0[1], _obj_0[2]
        end
        return displayValue or value
      end
    end,
    draw = function(self, ass, selected)
      if selected then
        ass:append(tostring(bold(self.displayText)) .. ": ")
      else
        ass:append(tostring(self.displayText) .. ": ")
      end
      if self:hasPrevious() then
        ass:append("◀ ")
      end
      ass:append(self:getDisplayValue())
      if self:hasNext() then
        ass:append(" ▶")
      end
      return ass:append("\\N")
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, optType, displayText, value, opts)
      self.optType = optType
      self.displayText = displayText
      self.opts = opts
      self.value = 1
      return self:setValue(value)
    end,
    __base = _base_0,
    __name = "Option"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Option = _class_0
end
local EncodeOptionsPage
do
  local _class_0
  local _parent_0 = Page
  local _base_0 = {
    getCurrentOption = function(self)
      return self.options[self.currentOption][2]
    end,
    leftKey = function(self)
      (self:getCurrentOption()):leftKey()
      return self:draw()
    end,
    rightKey = function(self)
      (self:getCurrentOption()):rightKey()
      return self:draw()
    end,
    prevOpt = function(self)
      self.currentOption = math.max(1, self.currentOption - 1)
      return self:draw()
    end,
    nextOpt = function(self)
      self.currentOption = math.min(#self.options, self.currentOption + 1)
      return self:draw()
    end,
    confirmOpts = function(self)
      for _, optPair in ipairs(self.options) do
        local optName, opt
        optName, opt = optPair[1], optPair[2]
        options[optName] = opt:getValue()
      end
      self:hide()
      return self.callback(true)
    end,
    cancelOpts = function(self)
      self:hide()
      return self.callback(false)
    end,
    draw = function(self)
      local window_w, window_h = mp.get_osd_size()
      local ass = assdraw.ass_new()
      ass:new_event()
      self:setup_text(ass)
      ass:append(tostring(bold('Options:')) .. "\\N\\N")
      for i, optPair in ipairs(self.options) do
        local opt = optPair[2]
        opt:draw(ass, self.currentOption == i)
      end
      ass:append("\\N▲ / ▼: navigate\\N")
      ass:append(tostring(bold('ENTER:')) .. " confirm options\\N")
      ass:append(tostring(bold('ESC:')) .. " cancel\\N")
      return mp.set_osd_ass(window_w, window_h, ass.text)
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, callback)
      self.callback = callback
      self.currentOption = 1
      local scaleHeightOpts = {
        possibleValues = {
          {
            -1,
            "no"
          },
          {
            240
          },
          {
            360
          },
          {
            480
          },
          {
            720
          },
          {
            1080
          },
          {
            1440
          },
          {
            2160
          }
        }
      }
      local filesizeOpts = {
        step = 250,
        min = 0,
        altDisplayNames = {
          [0] = "disabled"
        }
      }
      local formatIds = {
        "webm-vp8",
        "webm-vp9",
        "mp4",
        "raw"
      }
      local formatOpts = {
        possibleValues = (function()
          local _accum_0 = { }
          local _len_0 = 1
          for _index_0 = 1, #formatIds do
            local fId = formatIds[_index_0]
            _accum_0[_len_0] = {
              fId,
              formats[fId].displayName
            }
            _len_0 = _len_0 + 1
          end
          return _accum_0
        end)()
      }
      self.options = {
        {
          "output_format",
          Option("list", "Output Format", options.output_format, formatOpts)
        },
        {
          "twopass",
          Option("bool", "Two Pass", options.twopass)
        },
        {
          "apply_current_filters",
          Option("bool", "Apply Current Video Filters", options.apply_current_filters)
        },
        {
          "scale_height",
          Option("list", "Scale Height", options.scale_height, scaleHeightOpts)
        },
        {
          "strict_filesize_constraint",
          Option("bool", "Strict Filesize Constraint", options.strict_filesize_constraint)
        },
        {
          "target_filesize",
          Option("int", "Target Filesize", options.target_filesize, filesizeOpts)
        }
      }
      self.keybinds = {
        ["LEFT"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.leftKey
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["RIGHT"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.rightKey
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["UP"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.prevOpt
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["DOWN"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.nextOpt
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["ENTER"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.confirmOpts
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["ESC"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.cancelOpts
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)()
      }
    end,
    __base = _base_0,
    __name = "EncodeOptionsPage",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  EncodeOptionsPage = _class_0
end
local PreviewPage
do
  local _class_0
  local _parent_0 = Page
  local _base_0 = {
    prepare = function(self)
      local vf = mp.get_property_native("vf")
      vf[#vf + 1] = {
        name = "sub"
      }
      if self.region:is_valid() then
        vf[#vf + 1] = {
          name = "crop",
          params = {
            w = tostring(self.region.w),
            h = tostring(self.region.h),
            x = tostring(self.region.x),
            y = tostring(self.region.y)
          }
        }
      end
      mp.set_property_native("vf", vf)
      if self.startTime > -1 and self.endTime > -1 then
        mp.set_property_native("ab-loop-a", self.startTime)
        mp.set_property_native("ab-loop-b", self.endTime)
        mp.set_property_native("time-pos", self.startTime)
      end
      return mp.set_property_native("pause", false)
    end,
    dispose = function(self)
      mp.set_property("ab-loop-a", "no")
      mp.set_property("ab-loop-b", "no")
      for prop, value in pairs(self.originalProperties) do
        mp.set_property_native(prop, value)
      end
    end,
    draw = function(self)
      local window_w, window_h = mp.get_osd_size()
      local ass = assdraw.ass_new()
      ass:new_event()
      self:setup_text(ass)
      ass:append("Press " .. tostring(bold('ESC')) .. " to exit preview.\\N")
      return mp.set_osd_ass(window_w, window_h, ass.text)
    end,
    cancel = function(self)
      self:hide()
      return self.callback()
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, callback, region, startTime, endTime)
      self.callback = callback
      self.originalProperties = {
        ["vf"] = mp.get_property_native("vf"),
        ["time-pos"] = mp.get_property_native("time-pos"),
        ["pause"] = mp.get_property_native("pause")
      }
      self.keybinds = {
        ["ESC"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.cancel
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)()
      }
      self.region = region
      self.startTime = startTime
      self.endTime = endTime
      self.isLoop = false
    end,
    __base = _base_0,
    __name = "PreviewPage",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  PreviewPage = _class_0
end
local MainPage
do
  local _class_0
  local _parent_0 = Page
  local _base_0 = {
    setStartTime = function(self)
      self.startTime = mp.get_property_number("time-pos")
      if self.visible then
        self:clear()
        return self:draw()
      end
    end,
    setEndTime = function(self)
      self.endTime = mp.get_property_number("time-pos")
      if self.visible then
        self:clear()
        return self:draw()
      end
    end,
    draw = function(self)
      local window_w, window_h = mp.get_osd_size()
      local ass = assdraw.ass_new()
      ass:new_event()
      self:setup_text(ass)
      ass:append(tostring(bold('WebM maker')) .. "\\N\\N")
      ass:append(tostring(bold('c:')) .. " crop\\N")
      ass:append(tostring(bold('1:')) .. " set start time (current is " .. tostring(seconds_to_time_string(self.startTime)) .. ")\\N")
      ass:append(tostring(bold('2:')) .. " set end time (current is " .. tostring(seconds_to_time_string(self.endTime)) .. ")\\N")
      ass:append(tostring(bold('o:')) .. " change encode options\\N")
      ass:append(tostring(bold('p:')) .. " preview\\N")
      ass:append(tostring(bold('e:')) .. " encode\\N\\N")
      ass:append(tostring(bold('ESC:')) .. " close\\N")
      return mp.set_osd_ass(window_w, window_h, ass.text)
    end,
    onUpdateCropRegion = function(self, updated, newRegion)
      if updated then
        self.region = newRegion
      end
      return self:show()
    end,
    crop = function(self)
      self:hide()
      local cropPage = CropPage((function()
        local _base_1 = self
        local _fn_0 = _base_1.onUpdateCropRegion
        return function(...)
          return _fn_0(_base_1, ...)
        end
      end)(), self.region)
      return cropPage:show()
    end,
    onOptionsChanged = function(self, updated)
      return self:show()
    end,
    changeOptions = function(self)
      self:hide()
      local encodeOptsPage = EncodeOptionsPage((function()
        local _base_1 = self
        local _fn_0 = _base_1.onOptionsChanged
        return function(...)
          return _fn_0(_base_1, ...)
        end
      end)())
      return encodeOptsPage:show()
    end,
    onPreviewEnded = function(self)
      return self:show()
    end,
    preview = function(self)
      self:hide()
      local previewPage = PreviewPage((function()
        local _base_1 = self
        local _fn_0 = _base_1.onPreviewEnded
        return function(...)
          return _fn_0(_base_1, ...)
        end
      end)(), self.region, self.startTime, self.endTime)
      return previewPage:show()
    end,
    encode = function(self)
      self:hide()
      if self.startTime < 0 then
        message("No start time, aborting")
        return 
      end
      if self.endTime < 0 then
        message("No end time, aborting")
        return 
      end
      if self.startTime >= self.endTime then
        message("Start time is ahead of end time, aborting")
        return 
      end
      return encode(self.region, self.startTime, self.endTime)
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self)
      self.keybinds = {
        ["c"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.crop
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["1"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.setStartTime
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["2"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.setEndTime
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["o"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.changeOptions
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["p"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.preview
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["e"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.encode
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)(),
        ["ESC"] = (function()
          local _base_1 = self
          local _fn_0 = _base_1.hide
          return function(...)
            return _fn_0(_base_1, ...)
          end
        end)()
      }
      self.startTime = -1
      self.endTime = -1
      self.region = Region()
    end,
    __base = _base_0,
    __name = "MainPage",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  MainPage = _class_0
end
monitor_dimensions()
local mainPage = MainPage()
return mp.add_key_binding(options.keybind, "display-webm-encoder", (function()
  local _base_0 = mainPage
  local _fn_0 = _base_0.show
  return function(...)
    return _fn_0(_base_0, ...)
  end
end)(), {
  repeatable = false
})
