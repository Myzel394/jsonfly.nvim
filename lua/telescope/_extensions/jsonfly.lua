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
---
---@class Highlights
---@field number string - Highlight group for numbers, Default: "@number.json"
---@field boolean string - Highlight group for booleans, Default: "@boolean.json"
---@field string string - Highlight group for strings, Default: "@string.json"
---@field null string - Highlight group for null values, Default: "@constant.builtin.json"
---@field other string - Highlight group for other types, Default: "@label.json"

local parsers = require"jsonfly.parsers"
local json = require"jsonfly.json"
local utils = require"jsonfly.utils"

local json = require"jsonfly.json"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require"telescope.config".values
local make_entry = require "telescope.make_entry"
local entry_display = require "telescope.pickers.entry_display"

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
            local keys = parsers:get_entries_from_lua_json(parsed)

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
                    local keys = parsers:get_entries_from_lsp_symbols(result)

                    pickers.new(opts, {
                        prompt_title = opts.prompt_title,
                        finder = finders.new_table {
                            results = keys,
                            ---@param entry Entry
                            entry_maker = function(entry)
                                local _, raw_depth = entry.key:gsub("%.", ".")
                                local depth = (raw_depth or 0) + 1

                                return make_entry.set_default_entry_mt({
                                    value = current_buf,
                                    ordinal = entry.key,
                                    display = function(_)
                                        local preview, hl_group_key = utils:create_display_preview(entry.value, opts)

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
