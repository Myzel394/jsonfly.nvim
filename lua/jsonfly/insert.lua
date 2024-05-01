local utils = require"jsonfly.utils"

-- This string will be used to position the cursor properly.
-- Once everything is set, the cursor searches for this string and jumps to it.
-- After that, it will be removed immediately.
local CURSOR_SEARCH_HELPER = "_jsonFfFfFfLyY0904857CursorHelperRrRrRrR"

local M = {};

-- https://stackoverflow.com/a/24823383/9878135
function table.slice(tbl, first, last, step)
  local sliced = {}

  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end

  return sliced
end

---@param line string
---@param also_match_end_bracket boolean - Whether to also match only a closing bracket
---@return boolean - Whether the line contains an empty JSON object
local function line_contains_empty_json(line, also_match_end_bracket)
    -- Starting and ending on same line
    return string.match(line, ".*[%{%[]%s*[%}%]]%s*,?*%s*")
        -- Opening bracket on line
        or string.match(line, ".*[%{%[]%s*")
        -- Closing bracket on line
        or (also_match_end_bracket and string.match(line, ".*.*[%}%]]%s*,?%s*"))
end

---@param entry Entry
---@param key string
---@param index number
local function check_key_equal(entry, key, index)
    local splitted = utils:split_by_char(entry.key, ".")

    return splitted[index] == key
end

---Find the entry in `entries` with the most matching keys at the beginning based on the `keys`.
---Returns the index of the entry
---@param entries Entry[]
---@param keys string[]
---@return number|nil
local function find_best_fitting_entry(entries, keys)
    local entry_index
    local current_indexes = {1, #entries}

    for kk=1, #keys do
        local key = keys[kk]

        local start_index = current_indexes[1]
        local end_index = current_indexes[2]

        current_indexes = {nil, nil}

        for ii=start_index, end_index do
            if check_key_equal(entries[ii], key, kk) then
                if current_indexes[1] == nil then
                    current_indexes[1] = ii
                end

                current_indexes[2] = ii
            end
        end

        if current_indexes[1] == nil then
            -- No entries found
            break
        else
            entry_index = current_indexes[1]
        end
    end

    return entry_index
end

---@param keys KeyDescription
---@param index number - Index of the key
---@param lines string[] - Table to write the lines to
local function write_keys(keys, index, lines)
    local key = keys[index]

    if index == #keys then
        lines[#lines + 1] = "\"" .. key.key .. "\": \"" .. CURSOR_SEARCH_HELPER .. "\""
        return
    end

    if key.type == "object_wrapper" then
        local previous_line = lines[#lines] or ""
        if line_contains_empty_json(previous_line, true) or #lines == 0 then
            lines[#lines + 1] = "{"
        else
            lines[#lines] = previous_line .. " {"
        end

        write_keys(keys, index + 1, lines)

        lines[#lines + 1] = "}"
    elseif key.type == "key" then
        lines[#lines + 1] = "\"" .. key.key .. "\":"

        write_keys(keys, index + 1, lines)
    elseif key.type == "array_wrapper" then
        local previous_line = lines[#lines] or ""
        -- Starting and ending on same line
        if line_contains_empty_json(previous_line, true) or #lines == 0 then
            lines[#lines + 1] = "["
        else
            lines[#lines] = previous_line .. " ["
        end
        write_keys(keys, index + 1, lines)

        lines[#lines + 1] = "]"
    elseif key.type == "array_index" then
        local amount = tonumber(key.key)
        -- Write previous empty array objects
        for _=1, amount do
            lines[#lines + 1] = "{},"
        end

        write_keys(keys, index + 1, lines)
    end
end

---@param buffer number
---@param insertion_line number
local function add_comma(buffer, insertion_line)
    local BUFFER_SIZE = 5

    -- Find next non-empty character in reverse
    for ii=insertion_line, 0, -BUFFER_SIZE do
        local previous_lines = vim.api.nvim_buf_get_lines(
            buffer,
            math.max(0, ii - BUFFER_SIZE),
            ii,
            false
        )

        print("previous lins: " .. vim.inspect(previous_lines))

        if #previous_lines == 0 then
            return
        end

        for jj=#previous_lines, 1, -1 do
            local line = previous_lines[jj]

            for char_index=#line, 1, -1 do
                local char = line:sub(char_index, char_index)

                if char ~= " " and char ~= "\t" and char ~= "\n" and char ~= "\r" then
                    if char == "," or char == "{" or char == "[" then
                        return
                    end

                    -- Insert comma at position
                    local line_number = math.max(0, ii - BUFFER_SIZE) + jj - 1
                    vim.api.nvim_buf_set_text(
                        buffer,
                        line_number,
                        char_index,
                        line_number,
                        char_index,
                        {","}
                    )
                    return
                end
            end
        end
    end
end

---@return number - The new line number to be used, as the buffer has been modified
local function expand_empty_object(buffer, line_number)
    local line = vim.api.nvim_buf_get_lines(buffer, line_number, line_number + 1, false)[1] or ""

    if line_contains_empty_json(line, false) then
        vim.api.nvim_buf_set_lines(
            buffer,
            line_number,
            line_number + 1,
            false,
            {
                "{",
                "},"
            }
        )

        return line_number + 1
    end

    return line_number
end

---@param buffer number
function M:jump_to_cursor_helper(buffer)
    vim.fn.search(CURSOR_SEARCH_HELPER)

    -- Remove cursor helper
    local position = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_buf_set_text(
        buffer,
        position[1] - 1,
        position[2],
        position[1] - 1,
        position[2] + #CURSOR_SEARCH_HELPER,
        {""}
    )

    -- -- Go into insert mode
    vim.cmd [[execute "normal a"]]
end

---@param keys KeyDescription[]
---@param input_key_depth number
local function get_key_descriptor_index(keys, input_key_depth)
    local depth = 0
    local index = 0

    for ii=1, #keys do
        if keys[ii].type == "key" or keys[ii].type == "array_index" then
            depth = depth + 1
        end

        if depth >= input_key_depth then
            index = ii
            break
        end
    end

    return index
end

---@param entries Entry[]
---@param keys string[]
---@return integer|nil - The index of the entry
local function get_entry_by_keys(entries, keys)
    for ii=1, #entries do
        local entry = entries[ii]
        local splitted = utils:split_by_char(entry.key, ".")

        local found = true

        for jj=1, #keys do
            if keys[jj] ~= splitted[jj] then
                found = false
                break
            end
        end

        if found then
            return ii
        end
    end
end

---@param keys KeyDescription[]
---@return string[]
local function flat_key_description(keys)
    local flat_keys = {}

    for ii=1, #keys do
        if keys[ii].type == "key" then
            flat_keys[#flat_keys + 1] = keys[ii].key
        elseif keys[ii].type == "array_index" then
            flat_keys[#flat_keys + 1] = tostring(keys[ii].key)
        end
    end

    return flat_keys
end

---Subtracts indexes if there are other indexes before already
---This ensures that no extra objects are created in `write_keys`
---Example: Entry got 4 indexes, keys want to index `6`. This will subtract 4 from `6` to get `2`.
---@param entries Entry[]
---@param starting_keys KeyDescription[]
---@param key KeyDescription - Th key to be inserted; must be of type `array_index`; will be modified in-place
local function normalize_array_indexes(entries, starting_keys, key)
    local starting_keys_flat = flat_key_description(starting_keys)
    local starting_key_index = get_entry_by_keys(entries, starting_keys_flat)
    local entry = entries[starting_key_index]

    key.key = key.key - #entry.value
end

---@param entries Entry[] - Entries, they must be children of a top level array
---Counts how many top level children an array has
local function count_array_children(entries)
    for ii=1, #entries do
        if string.match(entries[ii].key, "^%d+$") then
            return ii
        end
    end

    return #entries
end

---@param entries Entry[]
---@param keys KeyDescription[]
---@param buffer number
function M:insert_new_key(entries, keys, buffer)
    -- Close current buffer
    vim.cmd [[quit!]]

    local input_key = flat_key_description(keys)
    local entry_index = find_best_fitting_entry(entries, input_key) or 0
    ---@type Entry
    local entry = entries[entry_index]

    ---@type KeyDescription[]
    local remaining_keys
    ---@type integer
    local existing_keys_index

    if entry == nil then
        -- Insert as root
        existing_keys_index = 0
        remaining_keys = table.slice(keys, 2, #keys)

        -- Top level array
        if entries[1].key == "0" then
            -- Normalize array indexes
            remaining_keys[1].key = remaining_keys[1].key - count_array_children(entries)
        end

        entry = {
            key = "",
            position = {
                key_start = 1,
                line_number = 1,
                value_start = 1
            }
        }
    else
        local existing_input_keys_depth = #utils:split_by_char(entry.key, ".") + 1
        existing_keys_index = get_key_descriptor_index(keys, existing_input_keys_depth)
        remaining_keys = table.slice(keys, existing_keys_index, #keys)

        if remaining_keys[1].type == "array_index" then
            local starting_keys = table.slice(keys, 1, existing_keys_index - 1)
            normalize_array_indexes(entries, starting_keys, remaining_keys[1])
        end
    end

    local _writes = {}
    write_keys(remaining_keys, 1, _writes)
    local writes = {}

    for ii=1, #_writes do
        if _writes[ii] == true then
            -- Unwrap table
            writes[#writes] = writes[#writes][1]
        else
            writes[#writes + 1] = _writes[ii]
        end
    end

    -- Hacky way to jump to end of object
    vim.api.nvim_win_set_cursor(0, {entry.position.line_number, entry.position.value_start})
    vim.cmd [[execute "normal %"]]

    local changes = #writes
    local start_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    -- Add comma to previous JSON entry
    add_comma(buffer, start_line)
    local new_start_line = expand_empty_object(buffer, start_line)

    if new_start_line ~= start_line then
        changes = changes + math.abs(new_start_line - start_line)
        start_line = new_start_line
    end

    -- Insert new lines
    vim.api.nvim_buf_set_lines(buffer, start_line, start_line, false, writes)

    -- Format lines
    vim.api.nvim_win_set_cursor(0, {start_line, 1})
    vim.cmd('execute "normal =' .. changes .. 'j"')

    M:jump_to_cursor_helper(buffer)
end

return M;
