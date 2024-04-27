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
local function write_keys(keys, index)
    local lines = {}
    local key = keys[index]

    if index == #keys then
        return {
            { "\"" .. key.key .. "\": \"" .. CURSOR_SEARCH_HELPER .. "\""},
            true
        }
    end

    local insertions = write_keys(keys, index + 1)

    if key.type == "object_wrapper" then
        lines[#lines + 1] = "{"

        for ii=1, #insertions do
            lines[#lines + 1] = insertions[ii]
        end

        lines[#lines + 1] = "}"
    elseif key.type == "key" then
        lines[#lines + 1] = "\"" .. key.key .. "\":"

        for ii=1, #insertions do
            lines[#lines + 1] = insertions[ii]
        end
    elseif key.type == "array_key" then
        lines[#lines + 1] = "\"" .. key.key .. "\":"

        for ii=1, #insertions do
            lines[#lines + 1] = insertions[ii]
        end
    elseif key.type == "array_wrapper" then
        lines[#lines + 1] = "["

        for ii=1, #insertions do
            lines[#lines + 1] = insertions[ii]
        end

        lines[#lines + 1] = "]"
    elseif key.type == "array_index" then
        local amount = tonumber(key.key)
        -- Write previous empty array objects
        for _=1, amount do
            lines[#lines + 1] = "{},"
        end

        -- Write key
        for ii=1, #insertions do
            lines[#lines + 1] = insertions[ii]
        end
    end

    return lines
end

---@param buffer number
---@param insertion_line number
local function add_comma(buffer, insertion_line)
    local BUFFER_SIZE = 5

    -- Find next non-empty character in reverse
    for ii=insertion_line, 0, -BUFFER_SIZE do
        local previous_lines = vim.api.nvim_buf_get_lines(buffer, ii - BUFFER_SIZE, ii, false)

        if #previous_lines == 0 then
            return
        end

        for jj=#previous_lines, 1, -1 do
            local line = previous_lines[jj]

            for char_index=#line, 1, -1 do
                local char = line:sub(char_index, char_index)

                if char ~= " " and char ~= "\t" and char ~= "\n" and char ~= "\r" then
                    if char == "," then
                        return
                    end

                    -- Insert comma at position
                    local line_number = ii - (BUFFER_SIZE - jj)
                    vim.api.nvim_buf_set_text(
                        buffer,
                        line_number - 1,
                        char_index,
                        line_number - 1,
                        char_index,
                        {","}
                    )
                    return
                end
            end
        end
    end
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
        if keys[ii].type == "key" or keys[ii].type == "array_key" or keys[ii].type == "array_index" then
            depth = depth + 1
        end

        if depth >= input_key_depth then
            print(vim.inspect(ii))
            index = ii
            break
        end
    end

    return index
end

---@param entries Entry[]
---@param keys KeyDescription[]
---@param buffer number
function M:insert_new_key(entries, keys, buffer)
    -- Close current buffer
    vim.cmd [[quit!]]
    
    local input_key = {}

    for ii=1, #keys do
        if keys[ii].type == "key" then
            input_key[#input_key+1] = keys[ii].key
        elseif keys[ii].type == "array_index" then
            input_key[#input_key+1] = keys[ii].key
        end
    end

    print(vim.inspect(input_key))

    local entry_index = find_best_fitting_entry(entries, input_key) or 0
    local entry = entries[entry_index]
    local existing_input_keys_depth = #utils:split_by_char(entry.key, ".") + 1
    local existing_keys_index = get_key_descriptor_index(keys, existing_input_keys_depth)
    local remaining_keys = table.slice(keys, existing_keys_index, #keys)

    local _writes = write_keys(remaining_keys, 1)
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

    local start_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    -- Add comma to previous JSON entry
    add_comma(buffer, start_line)

    -- Insert new lines
    vim.api.nvim_buf_set_lines(buffer, start_line, start_line, false, writes)

    -- Format lines
    vim.api.nvim_win_set_cursor(0, {start_line, 1})
    vim.cmd('execute "normal =' .. #writes .. 'j"')

    M:jump_to_cursor_helper(buffer)
end

return M;
