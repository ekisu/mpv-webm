-- From https://gist.github.com/Kubuxu/e5e04c028d8aaeab4be8, works with big-endian order.
read_double = (bytes) ->
    sign = 1
    mantissa = bytes[2] % 2^4
    for i = 3, 8
        mantissa = mantissa * 256 + bytes[i]
    if bytes[1] > 127
        sign = -1

    exponent = (bytes[1] % 128) * 2^4 + math.floor(bytes[2] / 2^4)

    if exponent == 0
        return 0

    mantissa = (math.ldexp(mantissa, -52) + 1) * sign
    return math.ldexp(mantissa, exponent - 1023)

write_double = (num) ->
    bytes = {0,0,0,0,0,0,0,0}
    if num == 0
        return bytes

    anum = math.abs(num)

    mantissa, exponent = math.frexp(anum)
    exponent = exponent - 1
    mantissa = mantissa * 2 - 1
    sign = num ~= anum and 128 or 0
    exponent = exponent + 1023

    bytes[1] = sign + math.floor(exponent / 2^4)
    mantissa = mantissa * 2^4
    currentmantissa = math.floor(mantissa)
    mantissa = mantissa - currentmantissa
    bytes[2] = (exponent % 2^4) * 2^4 + currentmantissa
    for i= 3, 8
        mantissa = mantissa * 2^8
        currentmantissa = math.floor(mantissa)
        mantissa = mantissa - currentmantissa
        bytes[i] = currentmantissa
    return bytes

-- Represents the FIRSTPASS_STATS struct of libvpx-vp8.
class FirstpassStats
    duration_multiplier = 10000000.0
    fields_before_duration = 16
    fields_after_duration = 1

    new: (before_duration, duration, after_duration) =>
        @binary_data_before_duration = before_duration
        @binary_duration = duration
        @binary_data_after_duration = after_duration
    
    -- All fields are doubles = 8 bytes.
    @data_before_duration_size: () => fields_before_duration * 8
    @data_after_duration_size: () => fields_after_duration * 8
    @size: () => (fields_before_duration + 1 + fields_after_duration) * 8

    get_duration: () =>
        big_endian_binary_duration = reverse(@binary_duration)
        read_double(reversed_binary_duration) / duration_multiplier
    
    set_duration: (duration) =>
        big_endian_binary_duration = write_double(duration * duration_multiplier)
        @binary_duration = reverse(big_endian_binary_duration)

    @from_bytes: (bytes) =>
        before_duration = [b for b in *bytes[1, @data_before_duration_size!]]
        duration = [b for b in *bytes[@data_before_duration_size! + 1, @data_before_duration_size! + 8]]
        after_duration = [b for b in *bytes[@data_before_duration_size! + 8 + 1,]]
        return self(before_duration, duration, after_duration)
    
    _bytes_to_string: (bytes) =>
        string.char(unpack(bytes))

    as_binary_string: () =>
        before_duration_string = self\_bytes_to_string(@binary_data_before_duration)
        duration_string = self\_bytes_to_string(@binary_duration)
        after_duration_string = self\_bytes_to_string(@binary_data_after_duration)
        return before_duration_string .. duration_string .. after_duration_string

read_logfile_into_stats_array = (logfile_path) ->
    file = assert(io.open(logfile_path, "rb"))
    logfile_string = base64_decode(file\read!)
    file\close!

    stats_size = FirstpassStats\size!

    assert(logfile_string\len! % stats_size == 0)

    stats = {}
    for offset=1,#logfile_string,stats_size
        bytes = { logfile_string\byte(offset, offset + stats_size - 1) }
        assert(#bytes == stats_size)
        stats[#stats + 1] = FirstpassStats\from_bytes(bytes)
    return stats

write_stats_array_to_logfile = (stats_array, logfile_path) ->
    file = assert(io.open(logfile_path, "wb"))
    logfile_string = ""

    for stat in *stats_array
        logfile_string ..= stat\as_binary_string!
    
    file\write(base64_encode(logfile_string))
    file\close!

vp8_patch_logfile = (logfile_path, encode_total_duration) ->
    stats_array = read_logfile_into_stats_array(logfile_path)
    -- Last FirstpassStats is a aggregated one.
    average_duration = encode_total_duration / (#stats_array - 1)

    for i=1, #stats_array - 1
        stats_array[i]\set_duration(average_duration)
    
    stats_array[#stats_array]\set_duration(encode_total_duration)
    
    write_stats_array_to_logfile(stats_array, logfile_path)
