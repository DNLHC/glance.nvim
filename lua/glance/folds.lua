local config = require('glance.config')
local M = {}

M.folded = {}

function M.is_folded(filename)
  local fold = M.folded[filename]
  if config.options.folds.folded then
    return fold ~= false
  end
  return fold == true
end

function M.toggle(filename)
  M.folded[filename] = not M.is_folded(filename)
end

function M.close(filename)
  M.folded[filename] = true
end

function M.open(filename)
  M.folded[filename] = false
end

function M.reset()
  M.folded = {}
end

return M
