local json = require"jsonfly.json"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values
local make_entry = require "telescope.make_entry"

local function get_recursive_keys(t)
    local keys = {}

    for k, raw_value in pairs(t) do
        table.insert(keys, {key = k, entry = raw_value})

        local v = raw_value[0]

        if type(v) == "table" then
            local sub_keys = get_recursive_keys(v)
            for _, sub_key in ipairs(sub_keys) do
                table.insert(keys, {key = k .. "." .. sub_key.key, entry = sub_key.entry})
            end
        end
    end

    return keys
end

return require"telescope".register_extension {
    setup = function() end,
    exports = {
        jsonfly = function(opts)
            opts = opts or {}

            local current_buf = vim.api.nvim_get_current_buf()
            local filename = vim.api.nvim_buf_get_name(current_buf)
            local content_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
            local content = table.concat(content_lines, "\n")

            local parsed = json:decode(content)
            local keys = get_recursive_keys(parsed)

            print(vim.inspect(keys))

            pickers.new(opts, {
                prompt_title = "colors",
                finder = finders.new_table {
                    results = keys,
                    entry_maker = function(entry)
                        return make_entry.set_default_entry_mt({
                            value = vim.inspect(entry.entry[0]),
                            ordinal = entry.key,
                            display = entry.key,

                            bufnr = current_buf,
                            filename = filename,
                            lnum = entry.entry.newlines + 1,

                            indicator = 0,
                            extra = 0,
                        }, opts)
                    end,
                },
                previewer = conf.grep_previewer(opts),
                sorter = conf.generic_sorter(opts),
            }):find()
        end
    }
}
