local options_file_contents = io.open("src/options.lua", "r"):read("*a")
-- Get contents between brackets
local _, _, options = options_file_contents:find("(%b{})")
-- Remove brackets
local _, _, options = options:find("^{(.*)}$")
-- Print line by line
for line in options:gmatch("(.-)\n") do
    -- Trim whitespace
    line = line:gsub("^%s*(.-)%s*$", "%1")
    
    if line ~= "" then
        -- Change comments from -- to #
        line = line:gsub("^[-][-]", "#")
        -- Remove whitespace between key-value pairs, and ending comma
        if not line:find("^#") then
            local _, _, key, value = line:find("^(.-)%s*=%s*(.-),?$")

            -- Change true to yes, and false to no
            value = value:gsub("^true$", "yes")
            value = value:gsub("^false$", "no")

            -- Remove quotes and [[]]
            value = value:gsub("\"(.-)\"", "%1")
            value = value:gsub("[[][[](.-)[]][]]", "%1") -- ?

            line = key .. "=" .. value
        end

        print(line)       
    end
end
