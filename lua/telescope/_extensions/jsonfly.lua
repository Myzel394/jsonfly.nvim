--- Type definitions
---@class Options
---@field key_max_length number - Length for the key column, 0 for no column-like display, Default: 50
---@field max_length number - Maximum length for the value column, Default: 9999 (basically no limit)
---@field overflow_marker string - Marker for truncated values, Default: "…"
---@field conceal boolean|"auto" - Whether to conceal strings, If `true` strings will be concealed, If `false` strings will be displayed as they are, If `"auto"` strings will be concealed if `conceallevel` is greater than 0, Default: "auto"
---@field prompt_title string - Title for the prompt, Default: "JSON(fly)"
---@field highlights Highlights - Highlight groups for different types
---
---@class Highlights
---@field number string - Highlight group for numbers, Default: "@number.json"
---@field boolean string - Highlight group for booleans, Default: "@boolean.json"
---@field string string - Highlight group for strings, Default: "@string.json"
---@field null string - Highlight group for null values, Default: "@constant.builtin.json"
---@field other string - Highlight group for other types, Default: "@label.json"

local json = require"jsonfly.json"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values
local make_entry = require "telescope.make_entry"
local entry_display = require "telescope.pickers.entry_display"

local function get_recursive_keys(t)
    local keys = {}

    for k, raw_value in pairs(t) do
        table.insert(keys, {key = k, entry = raw_value})

        local v = raw_value.value

        if type(v) == "table" then
            local sub_keys = get_recursive_keys(v)
            for _, sub_key in ipairs(sub_keys) do
                table.insert(keys, {key = k .. "." .. sub_key.key, entry = sub_key.entry})
            end
        end
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
            table.insert(preview_table, k .. ": " .. create_display_preview(v.value, opts))
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

return require"telescope".register_extension {
    setup = function() end,
    exports = {
        ---@param opts Options
        jsonfly = function(opts)
            opts = opts or {}
            opts.prompt_title = opts.prompt_title or "JSON(fly)"
            opts.key_max_length = opts.key_max_length or 50
            opts.max_length = opts.max_length or 9999
            opts.overflow_marker = opts.overflow_marker or "…"
            opts.highlights = opts.highlights or {
                string = "@string.json",
                number = "@number.json",
                boolean = "@boolean.json",
                null = "@constant.builtin.json",
                other = "@label.json",
            }

            if opts.conceal == nil then
                opts.conceal = "auto"
            end

            local current_buf = vim.api.nvim_get_current_buf()
            local filename = vim.api.nvim_buf_get_name(current_buf)
            local content_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
            local content = table.concat(content_lines, "\n")

            local parsed = json:decode(content)
            local keys = get_recursive_keys(parsed)

            local displayer = entry_display.create {
                separator = " ",
                items = {
                    { width = 1 },
                    { width = opts.key_max_length },
                    { remaining = true },
                },
            }

            pickers.new(opts, {
                prompt_title = opts.prompt_title,
                finder = finders.new_table {
                    results = keys,
                    entry_maker = function(entry)
                        local _, raw_depth = entry.key:gsub("%.", ".")
                        local depth = (raw_depth or 0) + 1

                        return make_entry.set_default_entry_mt({
                            value = current_buf,
                            ordinal = entry.key,
                            display = function(_)
                                local preview, hl_group_key = create_display_preview(entry.entry.value, opts)

                                return displayer {
                                    { depth, "TelescopeResultsNumber"},
                                    { entry.key, "@property.json" },
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
                            lnum = entry.entry.newlines + 1,
                            col = entry.entry.relative_start,
                        }, opts)
                    end,
                },
                previewer = conf.grep_previewer(opts),
                sorter = conf.generic_sorter(opts),
                sorting_strategy = "ascending",
            }):find()
        end
    }
}
