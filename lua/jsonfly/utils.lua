---@class KeyDescription
---@field key string
---@field type "object"|"array"|"string"

local M = {}

function M:truncate_overflow(value, max_length, overflow_marker)
    if vim.fn.strdisplaywidth(value) > max_length then
        return value:sub(1, max_length - vim.fn.strdisplaywidth(overflow_marker)) .. overflow_marker
    end

    return value
end

---@param value any
---@param conceal boolean
function M:create_display_preview(value, conceal)
    local t = type(value)

    if t == "table" then
        local preview_table = {}

        for k, v in pairs(value) do
            preview_table[#preview_table + 1] = k .. ": " .. M:create_display_preview(v, conceal)
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
function M:replace_previous_keys(key, replacement)
    for i = #key, 1, -1 do
        if key:sub(i, i) == "." then
            local len = i - 1
            local before = replacement:rep(len)

            return before .. "." .. key:sub(i + 1)
        end
    end

    return key
end

---@param text string
---@param char string
---@return string[]
function M:split_by_char(text, char)
    local parts = {}
    local current = ""

    for i = 1, #text do
        local c = text:sub(i, i)

        if c == char then
            parts[#parts + 1] = current
            current = ""
        else
            current = current .. c
        end
    end

    parts[#parts + 1] = current

    return parts
end

---@param text string
---@return KeyDescription[]
function M:extract_key_description(text)
    local keys = {}

    local splitted = M:split_by_char(text, ".")
    for index=1, #splitted do
        local token = splitted[index]

        if string.sub(token, 1, 1) == "[" then
            keys[#keys + 1] = {
                key = tonumber(string.sub(token, 2, -2)),
                type = "array",
            }
        else
            keys[#keys + 1] = {
                key = token,
                type = "object",
            }
        end
    end

    if #keys == 0 then
        return {
            {
                key = text,
                type = "string",
            }
        }
    end

    return keys
end

return M
