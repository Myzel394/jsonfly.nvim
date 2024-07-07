local M = {};

---Only keep entries that are a parent of the child that is at the given position.
---This is useful to remove all entries that are not relevant to the current cursor position for example.
---Modifies the given `symbol` in place.
---@param symbol Symbol
---@param position Position
function M:filter_lsp_symbol_by_position(symbol, position)
    if type(symbol.children) == "table" and #symbol.children > 0 then
        for index=1, #symbol.children do
            local child = symbol.children[index]

            print("child", vim.inspect(child));
            self:filter_lsp_symbol_by_position(child, position)
        end
    end

    local r = symbol.selectionRange
    -- Let's just do a simple check
    if r.start.line >= position.line and r["end"].line <= position.line then
        return true
    end

    return false
end


return M;
