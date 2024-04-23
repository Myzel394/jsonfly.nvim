---@class EntryPosition
---@field line_number number
---@field key_start number
---@field value_start number
--
---@class Entry
---@field key string
---@field value Entry|table|number|string|boolean|nil
---@field position EntryPosition
--
---@class JSONEntry
---@field value JSONEntry|string|number|boolean|nil
---@field line_number number
---@field value_start number
---@field key_start number

local PRIMITIVE_TYPES = {
    string = true,
    number = true,
    boolean = true,
}

local M = {}

---@param entry JSONEntry
local function get_contents_from_json_value(entry)
    local value = entry.value

    if type(value) == "table" then
        -- Recursively get the contents of the table
        local contents = {}

        for k, v in pairs(value) do
            contents[k] = get_contents_from_json_value(v)
        end

        return contents
    else
        return entry.value
    end
end

---@param t table|nil|string|number|boolean
---@return Entry[]
function M:get_entries_from_lua_json(t)
    if PRIMITIVE_TYPES[type(t)] or t == nil then
        return {}
    end

    local keys = {}

    for k, _raw_value in pairs(t) do
        ---@type JSONEntry
        local raw_value = _raw_value
        ---@type Entry
        local entry = {
            key = tostring(k),
            value = get_contents_from_json_value(raw_value),
            position = {
                line_number = raw_value.line_number,
                key_start = raw_value.key_start,
                value_start = raw_value.value_start,
            }
        }
        table.insert(keys, entry)

        local v = raw_value.value

        if type(v) == "table" then
            local sub_keys = M:get_entries_from_lua_json(v)

            for index=1, #sub_keys do
                local sub_key = sub_keys[index]

                ---@type Entry
                local entry = {
                    key = k .. "." .. sub_key.key,
                    value = sub_key.value,
                    position = sub_key.position,
                }

                keys[#keys + 1] = entry
            end
        end
    end

    return keys
end

---@param result Symbol
---@return string|number|table|boolean|nil
function M:parse_lsp_value(result)
    -- Object
    if result.kind == 2 then
        local value = {}

        for _, child in ipairs(result.children) do
            value[child.name] = M:parse_lsp_value(child)
        end

        return value
    -- Integer
    elseif result.kind == 16 then
        return tonumber(result.detail)
    -- String
    elseif result.kind == 15 then
        return result.detail
    -- Array
    elseif result.kind == 18 then
        local value = {}

        for i, child in ipairs(result.children) do
            value[i] = M:parse_lsp_value(child)
        end

        return value
    -- null
    elseif result.kind == 13 then
        return nil
    -- boolean
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
function M:get_entries_from_lsp_symbols(symbols)
    local keys = {}

    for index=1, #symbols do
        local symbol = symbols[index]
        local key = symbol.name

        ---@type Entry
        local entry = {
            key = tostring(key),
            value = M:parse_lsp_value(symbol),
            position = {
                line_number = symbol.range.start.line + 1,
                key_start = symbol.range.start.character + 2,
                -- The LSP doesn't return the start of the value, so we'll just assume it's 3 characters after the key
                -- We assume a default JSON file like:
                -- `"my_key": "my_value"`
                -- Since we get the end of the key, we can just add 4 to get the start of the value
                value_start = symbol.selectionRange["end"].character + 3,
            }
        }
        keys[#keys + 1] = entry

        if symbol.kind == 2 or symbol.kind == 18 then
            local sub_keys = M:get_entries_from_lsp_symbols(symbol.children)

            for jindex=1, #sub_keys do
                ---@type Entry
                local entry = {
                    key = key .. "." .. sub_keys[jindex].key,
                    value = sub_keys[jindex].value,
                    position = sub_keys[jindex].position,
                }

                keys[#keys + 1] = entry
            end
        end
    end

    return keys
end

return M
