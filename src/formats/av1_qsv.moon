class AV1QSV extends Format
 new: =>
  @displayName = "AV1 (QSV/AAC)"
  @supportsTwopass = false
  @videoCodec = "av1_qsv"
  @audioCodec = "aac"
  @outputExtension = "mp4"
  @acceptsBitrate = true

 getFlags: =>
  {
   "--ovcopts-add=async_depth=#{options.threads}"
  }

formats["av1_qsv"] = AV1QSV!
