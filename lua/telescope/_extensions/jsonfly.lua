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
---@field show_nested_child_preview boolean - Whether to show a preview of nested children, Default: true
---@field backend "lua"|"lsp" - Backend to use for parsing JSON, "lua" = Use our own Lua parser to parse the JSON, "lsp" = Use your LSP to parse the JSON (currently only https://github.com/Microsoft/vscode-json-languageservice is supported). If the "lsp" backend is selected but the LSP fails, it will fallback to the "lua" backend, Default: "lsp"
---@field use_cache number - Whether to use cache the parsed JSON. The cache will be activated if the number of lines is greater or equal to this value, By default, the cache is activate when the file if 1000 lines or more; `0` to disable the cache, Default: 500
---@field commands Commands - Shortcuts for commands
--
---@class Commands
---@field add_key string[] - Add the currently entered key to the JSON. Must be of type [string, string] <mode, key>; Example: {"n", "a"} -> When in normal mode, press "a" to add the key; Example: {"i", "<C-a>"} -> When in insert mode, press <C-a> to add the key; Default: {"i", "<C-a>"}
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
local insert = require"jsonfly.insert"

local json = require"jsonfly.json"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values
local make_entry = require "telescope.make_entry"
local entry_display = require "telescope.pickers.entry_display"

local action_state = require "telescope.actions.state"

---@type Options
local DEFAULT_CONFIG = {
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
    show_nested_child_preview = true,
    backend = "lsp",
    use_cache = 500,
    commands = {
        add_key = {"i", "<C-a>"}
    }
}

local global_config = {}

---@param entries Entry[]
---@param buffer number
local function show_picker(entries, buffer, xopts)
    local config = vim.tbl_deep_extend("force", global_config, xopts or {})
    local filename = vim.api.nvim_buf_get_name(buffer)

    local displayer = entry_display.create {
        separator = " ",
        items = {
            { width = 1 },
            global_config.key_exact_length and { width = global_config.key_max_length } or { remaining = true },
            { remaining = true },
        },
    }
    ---@type boolean
    local conceal

    if global_config.conceal == "auto" then
        conceal = vim.o.conceallevel > 0
    else
        conceal = global_config.conceal == true
    end

    pickers.new(config, {
        prompt_title = global_config.prompt_title,
        attach_mappings = function(_, map)
            map(
                global_config.commands.add_key[1],
                global_config.commands.add_key[2],
                function(prompt_bufnr)
                    local current_picker = action_state.get_current_picker(prompt_bufnr)
                    local input = current_picker:_get_prompt()

                    local key_descriptor = utils:extract_key_description(input)

                    insert:insert_new_key(entries, key_descriptor, buffer)
                end
            )

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
                        local preview, hl_group_key = utils:create_display_preview(entry.value, conceal, global_config.show_nested_child_preview)

                        local key = global_config.subkeys_display == "normal" and entry.key or utils:replace_previous_keys(entry.key, " ")

                        return displayer {
                            { depth, "TelescopeResultsNumber"},
                            {
                                utils:truncate_overflow(
                                    key,
                                    global_config.key_max_length,
                                    global_config.overflow_marker
                                ),
                                "@property.json",
                            },
                            {
                                utils:truncate_overflow(
                                    preview,
                                    global_config.max_length,
                                    global_config.overflow_marker
                                ),
                                global_config.highlights[hl_group_key] or "TelescopeResultsString",
                            },
                        }
                    end,

                    bufnr = buffer,
                    filename = filename,
                    lnum = entry.position.line_number,
                    col = global_config.jump_behavior == "key_start"
                            and entry.position.key_start
                            -- Use length ("#" operator) as vim jumps to the bytes, not characters
                            or entry.position.value_start
                }, config)
            end,
        },
        previewer = conf.grep_previewer(config),
        sorter = conf.generic_sorter(config),
        sorting_strategy = "ascending",
    }):find()
end

return require("telescope").register_extension {
    setup = function(extension_config)
        global_config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, extension_config or {})
    end,
    exports = {
        jsonfly = function(xopts)
            local current_buf = vim.api.nvim_get_current_buf()

            local cached_entries = cache:get_cache(current_buf)

            if cached_entries ~= nil then
                show_picker(cached_entries, current_buf, xopts)
                return
            end

            local content_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
            local content = table.concat(content_lines, "\n")
            local allow_cache = global_config.use_cache > 0 and #content_lines >= global_config.use_cache

            if allow_cache then
                cache:register_listeners(current_buf)
            end

            local function run_lua_parser()
                local parsed = json:decode(content)
                local entries = parsers:get_entries_from_lua_json(parsed)

                if allow_cache then
                    cache:cache_buffer(current_buf, entries)
                end

                show_picker(entries, current_buf, xopts)
            end

            if global_config.backend == "lsp" then
                local params = vim.lsp.util.make_position_params(xopts.winnr)

                vim.lsp.buf_request_all(
                    current_buf,
                    "textDocument/documentSymbol",
                    params,
                    function(response)
                        if response == nil or #response == 0 then
                            run_lua_parser()
                            return
                        end

                        local result = response[1].result

                        local entries = parsers:get_entries_from_lsp_symbols(result)

                        if allow_cache then
                            cache:cache_buffer(current_buf, entries)
                        end

                        show_picker(entries, current_buf, xopts)
                    end
                )
            else
                run_lua_parser()
            end
        end
    }
}
