local json = require"jsonfly.json"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values

local function get_recursive_keys(t)
  local keys = {}

  for k, v in pairs(t) do
    table.insert(keys, k)
    if type(v) == "table" then
      local subkeys = get_recursive_keys(v)
      for _, subkey in ipairs(subkeys) do
        table.insert(keys, k .. "." .. subkey)
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
              local content_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
              local content = table.concat(content_lines, "")

              local parsed = json:decode(content)

              print("keys" .. vim.inspect(parsed))

              pickers.new(opts, {
                prompt_title = "colors",
                finder = finders.new_table {
                  results = keys,
                },
                sorter = conf.generic_sorter(opts),
              }):find()
        end
    }
}
