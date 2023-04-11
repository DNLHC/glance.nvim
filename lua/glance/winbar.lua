local config = require('glance.config')

local Winbar = {}
Winbar.__index = Winbar

function Winbar:new(winnr)
  local scope = { sections = {}, winnr = winnr, last_values = {} }
  setmetatable(scope, self)
  return scope
end

function Winbar:append(key, group, opts)
  opts = opts or {}

  if group then
    group = config.hl_ns .. group
  end

  self.sections[key] = group
end

function Winbar:render(section_values)
  if vim.deep_equal(section_values, self.last_values) then
    return
  end

  local winbar_value = ''
  for section, value in pairs(section_values) do
    winbar_value =
      string.format('%s%%#%s# %s', winbar_value, self.sections[section], value)
  end

  self.last_values = section_values
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(self.winnr) then
      vim.api.nvim_win_set_option(self.winnr, 'winbar', winbar_value)
    end
  end)
end

return Winbar
