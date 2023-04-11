local config = require('glance.config')
local Renderer = {}
Renderer.__index = Renderer

function Renderer:new(bufnr)
  local scope =
    { lines = {}, hl = {}, line_nr = 0, current = '', bufnr = bufnr }
  setmetatable(scope, self)
  return scope
end

function Renderer:nl()
  table.insert(self.lines, self.current)
  self.current = ''
  self.line_nr = self.line_nr + 1
end

function Renderer:highlight()
  for _, line in ipairs(self.hl) do
    vim.api.nvim_buf_add_highlight(
      self.bufnr,
      config.namespace,
      line.group,
      line.line_nr,
      line.from,
      line.to
    )
  end
end

function Renderer:append(str, group, opts)
  str = str:gsub('[\n]', ' ')

  if type(opts) == 'string' then
    opts = { append = opts }
  end

  opts = opts or {}

  if group then
    group = config.hl_ns .. group
    local from = string.len(self.current)
    local hl = {
      line_nr = self.line_nr,
      from = from,
      to = from + string.len(str),
      group = group,
    }
    table.insert(self.hl, hl)
  end

  self.current = self.current .. str

  if opts.append then
    self.current = self.current .. opts.append
  end
end

function Renderer:render()
  return vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, self.lines)
end

return Renderer
