local M = {};

local _cache = {};

---@param buffer integer
function M:cache_buffer(buffer, value)
    _cache[buffer] = value;
end

---@param buffer integer
function M:invalidate_buffer(buffer)
    _cache[buffer] = nil;
end

---@param buffer integer
---@return string[]|nil
function M:get_cache(buffer)
    return _cache[buffer];
end

local _listening_buffers = {};

---@param buffer integer
function M:register_listeners(buffer)
    if _listening_buffers[buffer] then
        return;
    end

    _listening_buffers[buffer] = true;

    vim.api.nvim_buf_attach(
        buffer,
        false,
        {
            on_lines = function()
                self:invalidate_buffer(buffer)
            end,
            on_detach = function()
                self:invalidate_buffer(buffer)
                _listening_buffers[buffer] = nil;
            end,
        }
    );
end

return M;

