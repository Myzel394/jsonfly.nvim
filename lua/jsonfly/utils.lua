---@class KeyDescription
---@field key string
---@field type "object_wrapper"|"key"|"array_wrapper"|"array_index"

-- Examples:
--{
--  hello: [
--            {
--              test: "abc"
--            }
--         ]
--}
-- hello.[0].test
-- { key = "hello", type = "object" }
-- { type = "array" }
-- { type = "array_index", key = 0 }
-- { key = "test", type = "object" }
--
--{
--  hello: [
--           [
--             {
--               test: "abc"
--             }
--           ]
--         ]
--}
-- hello.[0].[0].test
-- { key = "hello", type = "object" }
-- { type = "array" }
-- { type = "array_index", key = 0 }
-- { type = "array" }
-- { type = "array_index", key = 0 }
-- { key = "test", type = "object" }
--
--{
--  hello: [
--           {},
--           [
--             {
--               test: "abc"
--             }
--           ]
--         ]
--}
-- hello.[1].[0].test
-- { key = "hello", type = "object" }
-- { type = "array" }
-- { type = "array_index", key = 1 }
-- { type = "array" }
-- { type = "array_index", key = 0 }
-- { key = "test", type = "object" }

local M = {}

function M:truncate_overflow(value, max_length, overflow_marker)
	if vim.fn.strdisplaywidth(value) > max_length then
		return value:sub(1, max_length - vim.fn.strdisplaywidth(overflow_marker)) .. overflow_marker
	end

	return value
end

---@param value any
---@param conceal boolean
---@param render_objects boolean
function M:create_display_preview(value, conceal, render_objects)
	local t = type(value)

	if t == "table" then
		if render_objects == false then
			return "", "other"
		end
		local preview_table = {}

		for k, v in pairs(value) do
			preview_table[#preview_table + 1] = k .. ": " .. M:create_display_preview(v, conceal, render_objects)
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
			return '"' .. value .. '"', "string"
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

	local index = 1

	while index <= #splitted do
		local token = splitted[index]

		-- Escape
		if string.sub(token, 1, 1) == "\\" then
			token = token:sub(2)

			keys[#keys + 1] = {
				type = "object_wrapper",
			}
			keys[#keys + 1] = {
				key = token,
				type = "key",
			}
		-- Array
		elseif string.match(token, "%[%d+%]") then
			local array_index = tonumber(string.sub(token, 2, -2))

			keys[#keys + 1] = {
				type = "array_wrapper",
			}
			keys[#keys + 1] = {
				key = array_index,
				type = "array_index",
			}
		-- Array
		elseif string.match(token, "%d+") then
			local array_index = tonumber(token)

			keys[#keys + 1] = {
				type = "array_wrapper",
			}
			keys[#keys + 1] = {
				key = array_index,
				type = "array_index",
			}
		-- Object
		else
			keys[#keys + 1] = {
				type = "object_wrapper",
			}
			keys[#keys + 1] = {
				key = token,
				type = "key",
			}
		end

		index = index + 1
	end

	if #keys == 0 then
		return {
			{
				key = text,
				type = "key",
			},
		}
	end

	return keys
end

---@param name string
---@return boolean
function M:is_module_available(name)
	return pcall(function()
		require(name)
	end) == true
end

return M
