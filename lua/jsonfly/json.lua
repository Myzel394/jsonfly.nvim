local VERSION = '20161109.21' -- version history at end of file
local AUTHOR_NOTE = "-[ JSON.lua package by Jeffrey Friedl (http://regex.info/blog/lua/json) version 20161109.21 ]-"

local OBJDEF = {
   VERSION      = VERSION,
   AUTHOR_NOTE  = AUTHOR_NOTE,
}



local default_pretty_indent  = "  "
local default_pretty_options = { pretty = true, align_keys = false, indent = default_pretty_indent  }

local isArray  = { __tostring = function() return "JSON array"         end }  isArray.__index  = isArray
local isObject = { __tostring = function() return "JSON object"        end }  isObject.__index = isObject

function OBJDEF:newArray(tbl)
   return setmetatable(tbl or {}, isArray)
end

function OBJDEF:newObject(tbl)
   return setmetatable(tbl or {}, isObject)
end




local function getnum(op)
   return type(op) == 'number' and op or op.N
end

local isNumber = {
   __tostring = function(T)  return T.S        end,
   __unm      = function(op) return getnum(op) end,

   __concat   = function(op1, op2) return tostring(op1) .. tostring(op2) end,
   __add      = function(op1, op2) return getnum(op1)   +   getnum(op2)  end,
   __sub      = function(op1, op2) return getnum(op1)   -   getnum(op2)  end,
   __mul      = function(op1, op2) return getnum(op1)   *   getnum(op2)  end,
   __div      = function(op1, op2) return getnum(op1)   /   getnum(op2)  end,
   __mod      = function(op1, op2) return getnum(op1)   %   getnum(op2)  end,
   __pow      = function(op1, op2) return getnum(op1)   ^   getnum(op2)  end,
   __lt       = function(op1, op2) return getnum(op1)   <   getnum(op2)  end,
   __eq       = function(op1, op2) return getnum(op1)   ==  getnum(op2)  end,
   __le       = function(op1, op2) return getnum(op1)   <=  getnum(op2)  end,
}
isNumber.__index = isNumber

function OBJDEF:asNumber(item)

   if getmetatable(item) == isNumber then
      -- it's already a JSON number object.
      return item
   elseif type(item) == 'table' and type(item.S) == 'string' and type(item.N) == 'number' then
      -- it's a number-object table that lost its metatable, so give it one
      return setmetatable(item, isNumber)
   else
      -- the normal situation... given a number or a string representation of a number....
      local holder = {
         S = tostring(item), -- S is the representation of the number as a string, which remains precise
         N = tonumber(item), -- N is the number as a Lua number.
      }
      return setmetatable(holder, isNumber)
   end
end

function OBJDEF:forceString(item)
   if type(item) == 'table' and type(item.S) == 'string' then
      return item.S
   else
      return tostring(item)
   end
end

function OBJDEF:forceNumber(item)
   if type(item) == 'table' and type(item.N) == 'number' then
      return item.N
   else
      return tonumber(item)
   end
end
   

local function unicode_codepoint_as_utf8(codepoint)
   --
   -- codepoint is a number
   --
   if codepoint <= 127 then
      return string.char(codepoint)

   elseif codepoint <= 2047 then
      --
      -- 110yyyxx 10xxxxxx         <-- useful notation from http://en.wikipedia.org/wiki/Utf8
      --
      local highpart = math.floor(codepoint / 0x40)
      local lowpart  = codepoint - (0x40 * highpart)
      return string.char(0xC0 + highpart,
                         0x80 + lowpart)

   elseif codepoint <= 65535 then
      --
      -- 1110yyyy 10yyyyxx 10xxxxxx
      --
      local highpart  = math.floor(codepoint / 0x1000)
      local remainder = codepoint - 0x1000 * highpart
      local midpart   = math.floor(remainder / 0x40)
      local lowpart   = remainder - 0x40 * midpart

      highpart = 0xE0 + highpart
      midpart  = 0x80 + midpart
      lowpart  = 0x80 + lowpart

      --
      -- Check for an invalid character (thanks Andy R. at Adobe).
      -- See table 3.7, page 93, in http://www.unicode.org/versions/Unicode5.2.0/ch03.pdf#G28070
      --
      if ( highpart == 0xE0 and midpart < 0xA0 ) or
         ( highpart == 0xED and midpart > 0x9F ) or
         ( highpart == 0xF0 and midpart < 0x90 ) or
         ( highpart == 0xF4 and midpart > 0x8F )
      then
         return "?"
      else
         return string.char(highpart,
                            midpart,
                            lowpart)
      end

   else
      --
      -- 11110zzz 10zzyyyy 10yyyyxx 10xxxxxx
      --
      local highpart  = math.floor(codepoint / 0x40000)
      local remainder = codepoint - 0x40000 * highpart
      local midA      = math.floor(remainder / 0x1000)
      remainder       = remainder - 0x1000 * midA
      local midB      = math.floor(remainder / 0x40)
      local lowpart   = remainder - 0x40 * midB

      return string.char(0xF0 + highpart,
                         0x80 + midA,
                         0x80 + midB,
                         0x80 + lowpart)
   end
end

function OBJDEF:onDecodeError(message, text, location, etc)
   if text then
      if location then
         message = string.format("%s at byte %d of: %s", message, location, text)
      else
         message = string.format("%s: %s", message, text)
      end
   end

   if etc ~= nil then
      message = message .. " (" .. OBJDEF:encode(etc) .. ")"
   end

   if self.assert then
      self.assert(false, message)
   else
      assert(false, message)
   end
end

function OBJDEF:onTrailingGarbage(json_text, location, parsed_value, etc)
   return self:onDecodeError("trailing garbage", json_text, location, etc)
end

OBJDEF.onDecodeOfNilError  = OBJDEF.onDecodeError
OBJDEF.onDecodeOfHTMLError = OBJDEF.onDecodeError

function OBJDEF:onEncodeError(message, etc)
   if etc ~= nil then
      message = message .. " (" .. OBJDEF:encode(etc) .. ")"
   end

   if self.assert then
      self.assert(false, message)
   else
      assert(false, message)
   end
end

local function grok_number(self, text, start, options)
   --
   -- Grab the integer part
   --
   local integer_part = text:match('^-?[1-9]%d*', start)
                     or text:match("^-?0",        start)

   if not integer_part then
      self:onDecodeError("expected number", text, start, options.etc)
      return nil, start -- in case the error method doesn't abort, return something sensible
   end

   local i = start + integer_part:len()

   --
   -- Grab an optional decimal part
   --
   local decimal_part = text:match('^%.%d+', i) or ""

   i = i + decimal_part:len()

   --
   -- Grab an optional exponential part
   --
   local exponent_part = text:match('^[eE][-+]?%d+', i) or ""

   i = i + exponent_part:len()

   local full_number_text = integer_part .. decimal_part .. exponent_part

   if options.decodeNumbersAsObjects then
      return OBJDEF:asNumber(full_number_text), i
   end

   --
   -- If we're told to stringify under certain conditions, so do.
   -- We punt a bit when there's an exponent by just stringifying no matter what.
   -- I suppose we should really look to see whether the exponent is actually big enough one
   -- way or the other to trip stringification, but I'll be lazy about it until someone asks.
   --
   if (options.decodeIntegerStringificationLength
       and
      (integer_part:len() >= options.decodeIntegerStringificationLength or exponent_part:len() > 0))

       or

      (options.decodeDecimalStringificationLength 
       and
       (decimal_part:len() >= options.decodeDecimalStringificationLength or exponent_part:len() > 0))
   then
      return full_number_text, i -- this returns the exact string representation seen in the original JSON
   end



   local as_number = tonumber(full_number_text)

   if not as_number then
      self:onDecodeError("bad number", text, start, options.etc)
      return nil, start -- in case the error method doesn't abort, return something sensible
   end

   return as_number, i
end


local function grok_string(self, text, start, options)

   if text:sub(start,start) ~= '"' then
      self:onDecodeError("expected string's opening quote", text, start, options.etc)
      return nil, start -- in case the error method doesn't abort, return something sensible
   end

   local i = start + 1 -- +1 to bypass the initial quote
   local text_len = text:len()
   local VALUE = ""
   while i <= text_len do
      local c = text:sub(i,i)
      if c == '"' then
         return VALUE, i + 1
      end
      if c ~= '\\' then
         VALUE = VALUE .. c
         i = i + 1
      elseif text:match('^\\b', i) then
         VALUE = VALUE .. "\b"
         i = i + 2
      elseif text:match('^\\f', i) then
         VALUE = VALUE .. "\f"
         i = i + 2
      elseif text:match('^\\n', i) then
         VALUE = VALUE .. "\n"
         i = i + 2
      elseif text:match('^\\r', i) then
         VALUE = VALUE .. "\r"
         i = i + 2
      elseif text:match('^\\t', i) then
         VALUE = VALUE .. "\t"
         i = i + 2
      else
         local hex = text:match('^\\u([0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF])', i)
         if hex then
            i = i + 6 -- bypass what we just read

            -- We have a Unicode codepoint. It could be standalone, or if in the proper range and
            -- followed by another in a specific range, it'll be a two-code surrogate pair.
            local codepoint = tonumber(hex, 16)
            if codepoint >= 0xD800 and codepoint <= 0xDBFF then
               -- it's a hi surrogate... see whether we have a following low
               local lo_surrogate = text:match('^\\u([dD][cdefCDEF][0123456789aAbBcCdDeEfF][0123456789aAbBcCdDeEfF])', i)
               if lo_surrogate then
                  i = i + 6 -- bypass the low surrogate we just read
                  codepoint = 0x2400 + (codepoint - 0xD800) * 0x400 + tonumber(lo_surrogate, 16)
               else
                  -- not a proper low, so we'll just leave the first codepoint as is and spit it out.
               end
            end
            VALUE = VALUE .. unicode_codepoint_as_utf8(codepoint)

         else

            -- just pass through what's escaped
            VALUE = VALUE .. text:match('^\\(.)', i)
            i = i + 2
         end
      end
   end

   self:onDecodeError("unclosed string", text, start, options.etc)
   return nil, start -- in case the error method doesn't abort, return something sensible
end

local function skip_whitespace(text, start)
   local _, match_end = text:find("^[ \n\r\t]+", start) -- [http://www.ietf.org/rfc/rfc4627.txt] Section 2
   if match_end then
      return match_end + 1
   else
      return start
   end
end

-- Count newlines in `text` up to `start`
local function count_newlines(text, start)
    local _, count = text:sub(1, start):gsub('\n', '\n')

    return count
end

-- Count characters from `i` to previous newline
-- {hello:sa\nmple\n    test}
local function get_relative_i(text, i)
    -- Find next newline from `i` backwards

    local count = 0

    for j = i, 1, -1 do
        if text:sub(j, j) == '\n' then
            break
        end
        count = count + 1
    end

    return count
end

local grok_one -- assigned later

local function grok_object(self, text, start, options)

   if text:sub(start,start) ~= '{' then
      self:onDecodeError("expected '{'", text, start, options.etc)
      return nil, start -- in case the error method doesn't abort, return something sensible
   end

   local i = skip_whitespace(text, start + 1) -- +1 to skip the '{'

   local VALUE = self.strictTypes and self:newObject { } or { }

   if text:sub(i,i) == '}' then
      return VALUE, i + 1
   end
   local text_len = text:len()
   while i <= text_len do
      local key, new_i = grok_string(self, text, i, options)

      ---- Find start of JSON key
      local key_start = i
      local key_end = new_i - 2
      local newlines = count_newlines(text, key_start)
      local relative_start = get_relative_i(text, key_start)

      i = skip_whitespace(text, new_i)

      if text:sub(i, i) ~= ':' then
         self:onDecodeError("expected colon", text, i, options.etc)
         return nil, i -- in case the error method doesn't abort, return something sensible
      end

      i = skip_whitespace(text, i + 1)

      local new_val, new_i = grok_one(self, text, i, options)

      ---- Add start position so we can quickly jump to it
      VALUE[key] = {
          value = new_val,
          key_start = key_start,
          key_end = key_end,
          newlines = newlines or 0,
          relative_start = relative_start,
      }

      --
      -- Expect now either '}' to end things, or a ',' to allow us to continue.
      --
      i = skip_whitespace(text, new_i)

      local c = text:sub(i,i)

      if c == '}' then
         return VALUE, i + 1
      end

      if text:sub(i, i) ~= ',' then
         self:onDecodeError("expected comma or '}'", text, i, options.etc)
         return nil, i -- in case the error method doesn't abort, return something sensible
      end

      i = skip_whitespace(text, i + 1)
   end

   self:onDecodeError("unclosed '{'", text, start, options.etc)
   return nil, start -- in case the error method doesn't abort, return something sensible
end

local function grok_array(self, text, start, options)
   if text:sub(start,start) ~= '[' then
      self:onDecodeError("expected '['", text, start, options.etc)
      return nil, start -- in case the error method doesn't abort, return something sensible
   end

   local i = skip_whitespace(text, start + 1) -- +1 to skip the '['
   local VALUE = self.strictTypes and self:newArray { } or { }
   if text:sub(i,i) == ']' then
      return VALUE, i + 1
   end

   local VALUE_INDEX = 1

   local text_len = text:len()
   while i <= text_len do
      local val, new_i = grok_one(self, text, i, options)
      local newlines = count_newlines(text, i)
      local relative_start = get_relative_i(text, i)

      -- can't table.insert(VALUE, val) here because it's a no-op if val is nil
      VALUE[VALUE_INDEX] = {
          value = val,
          key_start = new_i,
          key_end = new_i,
          newlines = newlines or 0,
          relative_start = relative_start,
      }
      VALUE_INDEX = VALUE_INDEX + 1

      i = skip_whitespace(text, new_i)

      --
      -- Expect now either ']' to end things, or a ',' to allow us to continue.
      --
      local c = text:sub(i,i)
      if c == ']' then
         return VALUE, i + 1
      end
      if text:sub(i, i) ~= ',' then
         self:onDecodeError("expected comma or ']'", text, i, options.etc)
         return nil, i -- in case the error method doesn't abort, return something sensible
      end
      i = skip_whitespace(text, i + 1)
   end
   self:onDecodeError("unclosed '['", text, start, options.etc)
   return nil, i -- in case the error method doesn't abort, return something sensible
end


grok_one = function(self, text, start, options)
   -- Skip any whitespace
   start = skip_whitespace(text, start)

   if start > text:len() then
      self:onDecodeError("unexpected end of string", text, nil, options.etc)
      return nil, start -- in case the error method doesn't abort, return something sensible
   end

   if text:find('^"', start) then
      return grok_string(self, text, start, options.etc)

   elseif text:find('^[-0123456789 ]', start) then
      return grok_number(self, text, start, options)

   elseif text:find('^%{', start) then
      return grok_object(self, text, start, options)

   elseif text:find('^%[', start) then
      return grok_array(self, text, start, options)

   elseif text:find('^true', start) then
      return true, start + 4

   elseif text:find('^false', start) then
      return false, start + 5

   elseif text:find('^null', start) then
      return nil, start + 4

   else
      self:onDecodeError("can't parse JSON", text, start, options.etc)
      return nil, 1 -- in case the error method doesn't abort, return something sensible
   end
end

function OBJDEF:decode(text, etc, options)
   --
   -- If the user didn't pass in a table of decode options, make an empty one.
   --
   if type(options) ~= 'table' then
      options = {}
   end

   --
   -- If they passed in an 'etc' argument, stuff it into the options.
   -- (If not, any 'etc' field in the options they passed in remains to be used)
   --
   if etc ~= nil then
      options.etc = etc
   end

   if text:match('^%s*$') then
      -- an empty string is nothing, but not an error
      return nil
   end

   if text:match('^%s*<') then
      -- Can't be JSON... we'll assume it's HTML
      local error_message = "HTML passed to JSON:decode()"
      self:onDecodeOfHTMLError(error_message, text, nil, options.etc)
      return nil, error_message -- in case the error method doesn't abort, return something sensible
   end

   --
   -- Ensure that it's not UTF-32 or UTF-16.
   -- Those are perfectly valid encodings for JSON (as per RFC 4627 section 3),
   -- but this package can't handle them.
   --
   if text:sub(1,1):byte() == 0 or (text:len() >= 2 and text:sub(2,2):byte() == 0) then
      local error_message = "JSON package groks only UTF-8, sorry"
      self:onDecodeError(error_message, text, nil, options.etc)
      return nil, error_message -- in case the error method doesn't abort, return something sensible
   end

   --
   -- apply global options
   --
   if options.decodeNumbersAsObjects == nil then
      options.decodeNumbersAsObjects = self.decodeNumbersAsObjects
   end
   if options.decodeIntegerStringificationLength == nil then
      options.decodeIntegerStringificationLength = self.decodeIntegerStringificationLength
   end
   if options.decodeDecimalStringificationLength == nil then
      options.decodeDecimalStringificationLength = self.decodeDecimalStringificationLength
   end

   --
   -- Finally, go parse it
   --
   local success, value, next_i = pcall(grok_one, self, text, 1, options)

   if success then

      local error_message = nil
      if next_i ~= #text + 1 then
         -- something's left over after we parsed the first thing.... whitespace is allowed.
         next_i = skip_whitespace(text, next_i)

         -- if we have something left over now, it's trailing garbage
         if next_i ~= #text + 1 then
            value, error_message = self:onTrailingGarbage(text, next_i, value, options.etc)
         end
      end
      return value, error_message

   else

      -- If JSON:onDecodeError() didn't abort out of the pcall, we'll have received
      -- the error message here as "value", so pass it along as an assert.
      local error_message = value
      if self.assert then
         self.assert(false, error_message)
      else
         assert(false, error_message)
      end
      -- ...and if we're still here (because the assert didn't throw an error),
      -- return a nil and throw the error message on as a second arg
      return nil, error_message

   end
end

function OBJDEF.__tostring()
   return "JSON encode/decode package"
end

OBJDEF.__index = OBJDEF

function OBJDEF:new(args)
   local new = { }

   if args then
      for key, val in pairs(args) do
         new[key] = val
      end
   end

   return setmetatable(new, OBJDEF)
end

return OBJDEF:new()


