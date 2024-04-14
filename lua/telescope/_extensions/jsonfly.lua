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
---
---@class Highlights
---@field number string - Highlight group for numbers, Default: "@number.json"
---@field boolean string - Highlight group for booleans, Default: "@boolean.json"
---@field string string - Highlight group for strings, Default: "@string.json"
---@field null string - Highlight group for null values, Default: "@constant.builtin.json"
---@field other string - Highlight group for other types, Default: "@label.json"

---- Types below are for internal use only ----
--
---@class EntryPosition
---@field line_number number
---@field key_start number
---@field value_start number
--
---@class Entry
---@field key string
---@field value Entry|table|number|string|boolean|nil
---@field position EntryPosition

local json = require"jsonfly.json"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values
local make_entry = require "telescope.make_entry"
local entry_display = require "telescope.pickers.entry_display"

---@param t table
---@return Entry[]
local function get_entries_from_lua_json(t)
    local keys = {}

    --@type k string
    --@type raw_value InputEntry
    for k, raw_value in pairs(t) do
        ---@type Entry
        local entry = {
            key = k,
            value = raw_value,
            position = {
                line_number = raw_value.newlines,
                key_start = raw_value.key_start,
                value_start = raw_value.value_start,
            }
        }
        table.insert(keys, entry)

        local v = raw_value.value

        if type(v) == "table" then
            local sub_keys = get_entries_from_lua_json(v)

            for _, sub_key in ipairs(sub_keys) do
                ---@type Entry
                local entry = {
                    key = k .. "." .. sub_key.key,
                    value = sub_key,
                    position = sub_key.position,
                }

                table.insert(keys, entry)
            end
        end
    end

    return keys
end

---@param result Symbol
---@return string|number|table|boolean|nil
local function parse_lsp_value(result)
    if result.kind == 2 then
        local value = {}

        for _, child in ipairs(result.children) do
            value[child.name] = parse_lsp_value(child)
        end

        return value
    elseif result.kind == 16 then
        return tonumber(result.detail)
    elseif result.kind == 15 then
        return result.detail
    elseif result.kind == 18 then
        local value = {}

        for i, child in ipairs(result.children) do
            value[i] = parse_lsp_value(child)
        end

        return value
    elseif result.kind == 13 then
        return nil
    elseif result.kind == 17 then
        return result.detail == "true"
    end
end


---@class Symbol
---@field name string
---@field kind number 2 = Object, 16 = Number, 15 = String, 18 = Array, 13 = Null, 17 = Boolean
---@field range Range
---@field selectionRange Range
---@field detail string
---@field children Symbol[]
--
---@class Range
---@field start Position
---@field ["end"] Position
--
---@class Position
---@field line number
---@field character number
--
---@param symbols Symbol[]
---@return Entry[]
local function get_entries_from_lsp_symbols(symbols)
    local keys = {}

    for _, symbol in ipairs(symbols) do
        local key = symbol.name

        if symbol.kind == 2 then
            local sub_keys = get_entries_from_lsp_symbols(symbol.children)

            for _, sub_key in ipairs(sub_keys) do
                ---@type Entry
                local entry = {
                    key = key .. "." .. sub_key.key,
                    value = sub_key.value,
                    position = sub_key.position,
                }

                table.insert(keys, entry)
            end
        end

        ---@type Entry
        local entry = {
            key = key,
            value = parse_lsp_value(symbol),
            position = {
                line_number = symbol.range["end"].line,
                key_start = symbol.range.start.character,
                value_start = symbol.selectionRange.start.character,
            }
        }
        table.insert(keys, entry)
    end

    return keys
end

local function truncate_overflow(value, max_length, overflow_marker)
    if vim.fn.strdisplaywidth(value) > max_length then
        return value:sub(1, max_length - vim.fn.strdisplaywidth(overflow_marker)) .. overflow_marker
    end

    return value
end

---@param value any
---@param opts Options
local function create_display_preview(value, opts)
    local t = type(value)
    local conceal

    if opts.conceal == "auto" then
        conceal = vim.o.conceallevel > 0
    else
        conceal = opts.conceal
    end

    if t == "table" then
        local preview_table = {}

        for k, v in pairs(value) do
            table.insert(preview_table, k .. ": " .. create_display_preview(v, opts))
        end

        return "{ " .. table.concat(preview_table, ", ") .. " }", "other"
    elseif t == "nil" then
        return "null", "null"
    elseif t == "number" then
        return tostring(value), "number"
    elseif t == "string" then
        if conceal then
            return value, "string"
        else
            return "\"" .. value .. "\"", "string"
        end
    elseif t == "boolean" then
        return value and "true" or "false", "boolean"
    end
end

---@param key string
---@param replacement string
---@return string
---Replaces all previous keys with the replacement
---Example: replace_previous_keys("a.b.c", "x") => "xxx.c"
local function replace_previous_keys(key, replacement)
    for i = #key, 1, -1 do
        if key:sub(i, i) == "." then
            local len = i - 1
            local before = replacement:rep(len)

            return before .. "." .. key:sub(i + 1)
        end
    end

    return key
end

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
}

return require"telescope".register_extension {
    setup = function(extension_config)
        opts = vim.tbl_deep_extend("force", opts, extension_config or {})
    end,
    exports = {
        jsonfly = function(xopts)
            local current_buf = vim.api.nvim_get_current_buf()
            local filename = vim.api.nvim_buf_get_name(current_buf)
            local content_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
            local content = table.concat(content_lines, "\n")

            local parsed = json:decode(content)
            local keys = get_entries_from_lua_json(parsed)

            local displayer = entry_display.create {
                separator = " ",
                items = {
                    { width = 1 },
                    opts.key_exact_length and { width = opts.key_max_length } or { remaining = true },
                    { remaining = true },
                },
            }

            local params = vim.lsp.util.make_position_params(xopts.winnr)
            local result = vim.lsp.buf_request(
                current_buf,
                "textDocument/documentSymbol",
                params,
                function(_, result)
                    local keys = get_entries_from_lsp_symbols(result)

                    pickers.new(opts, {
                        prompt_title = opts.prompt_title,
                        finder = finders.new_table {
                            results = keys,
                            ---@param entry Entry
                            entry_maker = function(entry)
                                local _, raw_depth = entry.key:gsub("%.", ".")
                                local depth = (raw_depth or 0) + 1

                                print(vim.inspect(entry))

                                return make_entry.set_default_entry_mt({
                                    value = current_buf,
                                    ordinal = entry.key,
                                    display = function(_)
                                        local preview, hl_group_key = create_display_preview(entry.value, opts)

                                        local key = opts.subkeys_display == "normal" and entry.key or replace_previous_keys(entry.key, " ")

                                        return displayer {
                                            { depth, "TelescopeResultsNumber"},
                                            {
                                                 truncate_overflow(
                                                    key,
                                                    opts.key_max_length,
                                                    opts.overflow_marker
                                                ),
                                                "@property.json",
                                            },
                                            {
                                                truncate_overflow(
                                                    preview,
                                                    opts.max_length,
                                                    opts.overflow_marker
                                                ),
                                                opts.highlights[hl_group_key] or "TelescopeResultsString",
                                            },
                                        }
                                    end,

                                    bufnr = current_buf,
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
            )

            -- pickers.new(opts, {
            --     prompt_title = opts.prompt_title,
            --     finder = finders.new_table {
            --         results = keys,
            --         entry_maker = function(entry)
            --             local _, raw_depth = entry.key:gsub("%.", ".")
            --             local depth = (raw_depth or 0) + 1
            --
            --             return make_entry.set_default_entry_mt({
            --                 value = current_buf,
            --                 ordinal = entry.key,
            --                 display = function(_)
            --                     local preview, hl_group_key = create_display_preview(entry.entry.value, opts)
            --
            --                     local key = opts.subkeys_display == "normal" and entry.key or replace_previous_keys(entry.key, " ")
            --
            --                     return displayer {
            --                         { depth, "TelescopeResultsNumber"},
            --                         {
            --                              truncate_overflow(
            --                                 key,
            --                                 opts.key_max_length,
            --                                 opts.overflow_marker
            --                             ),
            --                             "@property.json",
            --                         },
            --                         {
            --                             truncate_overflow(
            --                                 preview,
            --                                 opts.max_length,
            --                                 opts.overflow_marker
            --                             ),
            --                             opts.highlights[hl_group_key] or "TelescopeResultsString",
            --                         },
            --                     }
            --                 end,
            --
            --                 bufnr = current_buf,
            --                 filename = filename,
            --                 lnum = entry.entry.newlines + 1,
            --                 col = opts.jump_behavior == "key_start"
            --                         and entry.entry.key_start
            --                         -- Use length ("#" operator) as vim jumps to the bytes, not characters
            --                         or entry.entry.value_start
            --             }, opts)
            --         end,
            --     },
            --     previewer = conf.grep_previewer(opts),
            --     sorter = conf.generic_sorter(opts),
            --     sorting_strategy = "ascending",
            -- }):find()
        end
    }
}
