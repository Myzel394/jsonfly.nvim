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

local function create_display_preview(value)
    local t = type(value)

    if t == "table" then
        local preview_table = {}

        for k, v in pairs(value) do
            table.insert(preview_table, k .. ": " .. create_display_preview(v.value))
        end

        return "{ " .. table.concat(preview_table, ", ") .. " }", "@label.json"
    elseif t == "nil" then
        return "null", "@constant.builtin.json"
    elseif t == "number" then
        return tostring(value), "@number.json"
    elseif t == "string" then
        return value, "@string.json"
    elseif t == "boolean" then
        return value and "true" or "false", "@boolean.json"
    end
end

return require"telescope".register_extension {
    setup = function() end,
    exports = {
        jsonfly = function(opts)
            opts = opts or {}
            opts.key_max_length = opts.key_max_length or 50
            opts.max_length = opts.max_length or 9999
            opts.overflow_marker = opts.overflow_marker or "…"

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
                prompt_title = "colors",
                finder = finders.new_table {
                    results = keys,
                    entry_maker = function(entry)
                        local _, raw_depth = entry.key:gsub(".", ".")
                        local depth = (raw_depth or 0) + 1

                        return make_entry.set_default_entry_mt({
                            value = current_buf,
                            ordinal = entry.key,
                            display = function(_)
                                local preview, hl_group = create_display_preview(entry.entry.value)

                                return displayer {
                                    { depth, "TelescopeResultsNumber"},
                                    { entry.key .. ": ", "@property.json" },
                                    {
                                        truncate_overflow(
                                            preview,
                                            opts.max_length,
                                            opts.overflow_marker
                                        ),
                                        hl_group,
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
            }):find()
        end
    }
}
