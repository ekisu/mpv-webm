class HEVCQSV extends Format
 new: =>
  @displayName = "HEVC (QSV/AAC)"
  @supportsTwopass = false
  @videoCodec = "hevc_qsv"
  @audioCodec = "aac"
  @outputExtension = "mp4"
  @acceptsBitrate = true

 getFlags: =>
  {
   "--ovcopts-add=async_depth=#{options.threads}"
  }

formats["hevc_qsv"] = HEVCQSV!
