---- Documentation for jsonfly ----
--- Type definitions
---@class Options
---@field key_max_length number - Length for the key column, 0 for no column-like display, Default: 50
---@field key_exact_length boolean - Whether to use exact length for the key column, This will pad the key column with spaces to match the length, Default: false
---@field max_length number - Maximum length for the value column, Default: 9999 (basically no limit)
---@field overflow_marker string - Marker for truncated values, Default: "…"
---@field conceal boolean|"auto" - Whether to conceal strings, If `true` strings will be concealed, If `false` strings will be displayed as they are, If `"auto"` strings will be concealed if `conceallevel` is greater than 0, Default: "auto"
---@field prompt_title string - Title for the prompt, Default: "JSON(fly)"
---@field highlights Highlights - Highlight groups for different types
---@field jump_behavior "key_start"|"value_start" - Behavior for jumping to the location, "key_start" == Jump to the start of the key, "value_start" == Jump to the start of the value, Default: "key_start"
---@field subkeys_display "normal"|"waterfall" - Display subkeys in a normal or waterfall style, Default: "normal"
---@field backend "lua"|"lsp" - Backend to use for parsing JSON, "lua" = Use our own Lua parser to parse the JSON, "lsp" = Use your LSP to parse the JSON (currently only https://github.com/Microsoft/vscode-json-languageservice is supported). If the "lsp" backend is selected but the LSP fails, it will fallback to the "lua" backend, Default: "lsp"
---@field use_cache number - Whether to use cache the parsed JSON. The cache will be activated if the number of lines is greater or equal to this value, By default, the cache is activate when the file if 1000 lines or more; `0` to disable the cache, Default: 500
---
---@class Highlights
---@field number string - Highlight group for numbers, Default: "@number.json"
---@field boolean string - Highlight group for booleans, Default: "@boolean.json"
---@field string string - Highlight group for strings, Default: "@string.json"
---@field null string - Highlight group for null values, Default: "@constant.builtin.json"
---@field other string - Highlight group for other types, Default: "@label.json"

local parsers = require"jsonfly.parsers"
local utils = require"jsonfly.utils"
local cache = require"jsonfly.cache"

local json = require"jsonfly.json"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require"telescope.config".values
local make_entry = require "telescope.make_entry"
local entry_display = require "telescope.pickers.entry_display"

local action_state = require "telescope.actions.state"

---@type Options
local opts = {
    key_max_length = 50,
    key_exact_length = false,
    max_length = 9999,
    overflow_marker = "…",
    conceal = "auto",
    prompt_title = "JSON(fly)",
    highlights = {
        string = "@string.json",
        number = "@number.json",
        boolean = "@boolean.json",
        null = "@constant.builtin.json",
        other = "@label.json",
    },
    jump_behavior = "key_start",
    subkeys_display = "normal",
    backend = "lsp",
    use_cache = 500,
}

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

---@param entries Entry[]
---@param keys KeyDescription[]
---@return [Entry, string[]]
local function find_remaining_keys(entries, keys)
    local start_index = 1

    local existing_keys_depth = nil

    local potential_keys_indexes = {}

    for kk=1, #keys do
        local found_result = false
        local key = keys[kk].key

        for ii=start_index, #entries do
            if check_key_equal(entries[ii], key, kk) then
                found_result = true
                start_index = ii
                potential_keys_indexes[#potential_keys_indexes + 1] = ii
                -- Not sure if this can be used for optimization
                -- break
            end
        end

        if not found_result then
            existing_keys_depth = kk
            break
        end
    end

    if existing_keys_depth == nil then
        existing_keys_depth = #keys
    end

    local existing_keys = table.slice(keys, 1, existing_keys_depth - 1)
    local remaining_keys = table.slice(keys, existing_keys_depth, #keys)
    local existing_key_str = ""

    for ii=1, #existing_keys do
        existing_key_str = existing_key_str .. existing_keys[ii].key
        if ii < #existing_keys then
            existing_key_str = existing_key_str .. "."
        end
    end

    -- Find key that matches perfectly
    for ii=1, #potential_keys_indexes do
        local index = potential_keys_indexes[ii]
        local entry = entries[index]

        if entry.key == existing_key_str then
            return {entry, remaining_keys}
        end
    end

    -- Weird case, return the first one in hope that it's correct
    return {potential_keys_indexes[1], remaining_keys}
end

---@param keys KeyDescription
---@param index number - Index of the key
local function write_keys(keys, index)
    local lines = {}

    if index == #keys then
        return { "\"" .. keys[index].key .. "\": \"\""}
    end

    local insertions = write_keys(keys, index + 1)

    lines[#lines + 1] = "\"" .. keys[index].key .. "\": {"

    for ii=1, #insertions do
        lines[#lines + 1] = insertions[ii]
    end

    lines[#lines + 1] = "}"

    return lines
end

---@param entries Entry[]
---@param keys KeyDescription[]
---@param buffer number
local function insert_new_key(entries, keys, buffer)
    -- Close current buffer
    vim.cmd [[quit!]]

    local _result = find_remaining_keys(entries, keys)
    local entry = _result[1]
    local remaining_keys = _result[2]

    local writes = write_keys(remaining_keys, 1)
    vim.api.nvim_buf_set_lines(buffer, start_line, start_line, false, writes)

    print(vim.inspect(entry))
    print(vim.inspect(remaining_keys))
    print(vim.inspect(writes))

    -- for parts=#keys, 1, -1 do
    --     ---@type Entries[]
    --     local sub_keys = table.slice(keys, 1, parts)
    --     local path = ""
    --     
    --     for ii=1, #sub_keys do
    --         path = path .. sub_keys[ii].key
    --         if ii < #sub_keys then
    --             path = path .. "."
    --         end
    --     end
    --
    --     print(path)
    -- end
end

---@param entries Entry[]
---@param buffer number
local function show_picker(entries, buffer)
    local filename = vim.api.nvim_buf_get_name(buffer)

    local displayer = entry_display.create {
        separator = " ",
        items = {
            { width = 1 },
            opts.key_exact_length and { width = opts.key_max_length } or { remaining = true },
            { remaining = true },
        },
    }
    ---@type boolean
    local conceal

    if opts.conceal == "auto" then
        conceal = vim.o.conceallevel > 0
    else
        conceal = opts.conceal == true
    end

    pickers.new(opts, {
        prompt_title = opts.prompt_title,
        attach_mappings = function(_, map)
            map("i", "<C-a>", function(prompt_bufnr)
                  local current_picker = action_state.get_current_picker(prompt_bufnr)
                  local input = current_picker:_get_prompt()

                  local key_descriptor = utils:extract_key_description(input)

                  insert_new_key(entries, key_descriptor, buffer)
            end)

            return true
        end,
        finder = finders.new_table {
            results = entries,
            ---@param entry Entry
            entry_maker = function(entry)
                local _, raw_depth = entry.key:gsub("%.", ".")
                local depth = (raw_depth or 0) + 1

                return make_entry.set_default_entry_mt({
                    value = buffer,
                    ordinal = entry.key,
                    display = function(_)
                        local preview, hl_group_key = utils:create_display_preview(entry.value, conceal)

                        local key = opts.subkeys_display == "normal" and entry.key or utils:replace_previous_keys(entry.key, " ")

                        return displayer {
                            { depth, "TelescopeResultsNumber"},
                            {
                                utils:truncate_overflow(
                                    key,
                                    opts.key_max_length,
                                    opts.overflow_marker
                                ),
                                "@property.json",
                            },
                            {
                                utils:truncate_overflow(
                                    preview,
                                    opts.max_length,
                                    opts.overflow_marker
                                ),
                                opts.highlights[hl_group_key] or "TelescopeResultsString",
                            },
                        }
                    end,

                    bufnr = buffer,
                    filename = filename,
                    lnum = entry.position.line_number,
                    col = opts.jump_behavior == "key_start"
                            and entry.position.key_start
                            -- Use length ("#" operator) as vim jumps to the bytes, not characters
                            or entry.position.value_start
                }, opts)
            end,
        },
        previewer = conf.grep_previewer(opts),
        sorter = conf.generic_sorter(opts),
        sorting_strategy = "ascending",
    }):find()
end

return require"telescope".register_extension {
    setup = function(extension_config)
        opts = vim.tbl_deep_extend("force", opts, extension_config or {})
    end,
    exports = {
        jsonfly = function(xopts)
            local current_buf = vim.api.nvim_get_current_buf()

            local cached_entries = cache:get_cache(current_buf)

            if cached_entries ~= nil then
                show_picker(cached_entries, current_buf)
                return
            end

            local content_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
            local content = table.concat(content_lines, "\n")
            local allow_cache = opts.use_cache > 0 and #content_lines >= opts.use_cache

            if allow_cache then
                cache:register_listeners(current_buf)
            end

            local function run_lua_parser()
                local parsed = json:decode(content)
                local entries = parsers:get_entries_from_lua_json(parsed)

                if allow_cache then
                    cache:cache_buffer(current_buf, entries)
                end

                show_picker(entries, current_buf)
            end

            if opts.backend == "lsp" then
                local params = vim.lsp.util.make_position_params(xopts.winnr)

                vim.lsp.buf_request(
                    current_buf,
                    "textDocument/documentSymbol",
                    params,
                    function(error, lsp_response)
                        if error then
                            run_lua_parser()
                            return
                        end

                        local entries = parsers:get_entries_from_lsp_symbols(lsp_response)

                        if allow_cache then
                            cache:cache_buffer(current_buf, entries)
                        end

                        show_picker(entries, current_buf)
                    end
                )
            else
                run_lua_parser()
            end
        end
    }
}
