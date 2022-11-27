local config = require('glance.config')
local utils = require('glance.utils')
local Winbar = require('glance.winbar')

local Preview = {}
Preview.__index = Preview

local touched_bufs = {}

local winhl = {
  'Normal:GlancePreviewNormal',
  'CursorLine:GlancePreviewCursorLine',
  'SignColumn:GlancePreviewSignColumn',
  'EndOfBuffer:GlancePreviewEndOfBuffer',
  'LineNr:GlancePreviewLineNr',
}

-- Fails to set winhighlight in 0.7.2 for some reason
if vim.fn.has('nvim-0.8') == 1 then
  table.insert(winhl, 'GlanceNone:GlancePreviewMatch')
end

local win_opts = {
  winfixwidth = true,
  winfixheight = true,
  number = vim.wo.number,
  cursorline = true,
  cursorbind = false,
  scrollbind = false,
  wrap = true,
  winhighlight = table.concat(winhl, ','),
}

local float_win_opts = {
  'number',
  'relativenumber',
  'cursorline',
  'cursorcolumn',
  'foldcolumn',
  'spell',
  'list',
  'signcolumn',
  'colorcolumn',
  'fillchars',
  'winhighlight',
}

local function clear_hl(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, config.namespace, 0, -1)
  end
end

function Preview.create(opts)
  local preview = Preview:new(opts)
  return preview
end

function Preview:new(opts)
  win_opts.number = vim.api.nvim_win_get_option(opts.parent_winnr, 'number')

  local winnr = vim.api.nvim_open_win(opts.preview_bufnr, false, opts.win_opts)

  local scope = {
    winnr = winnr,
    bufnr = opts.preview_bufnr,
    parent_winnr = opts.parent_winnr,
    parent_bufnr = opts.parent_bufnr,
    current_location = nil,
    winbar = nil,
  }

  if config.options.winbar.enable then
    table.insert(float_win_opts, 'winbar')
    scope.winbar = Winbar:new(winnr)
    scope.winbar:append('filename', 'WinBarFilename')
    scope.winbar:append('filepath', 'WinBarFilepath')
  end

  setmetatable(scope, self)
  return scope
end

function Preview:is_valid()
  return self.winnr and vim.api.nvim_win_is_valid(self.winnr)
end

function Preview:on_attach_buffer()
  local bufnr = (self.current_location or {}).bufnr

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local keymap_opts = {
      buffer = bufnr,
      noremap = true,
      nowait = true,
      silent = true,
    }

    for key, action in pairs(config.options.mappings.preview) do
      vim.keymap.set('n', key, action, keymap_opts)
    end
  end
end

function Preview:on_detach_buffer()
  local bufnr = (self.current_location or {}).bufnr
  for lhs, _ in pairs(config.options.mappings.preview) do
    pcall(vim.api.nvim_buf_del_keymap, bufnr, 'n', lhs)
  end
end

function Preview:destroy()
  self.winnr = nil
  self.bufnr = nil
  self.parent_winnr = nil
  self.parent_bufnr = nil
  self.current_location = nil
  self.winbar = nil
end

function Preview:restore_win_opts()
  for opt, _ in pairs(win_opts) do
    if not vim.tbl_contains(float_win_opts, opt) then
      local value = vim.api.nvim_win_get_option(self.parent_winnr, opt)
      vim.api.nvim_win_set_option(self.winnr, opt, value)
    end
  end

  for _, opt in ipairs(float_win_opts) do
    local value = vim.api.nvim_win_get_option(self.parent_winnr, opt)
    vim.api.nvim_win_set_option(self.winnr, opt, value)
  end
end

function Preview:close()
  self:on_detach_buffer()
  self:restore_win_opts()

  if vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_win_close(self.winnr, {})
  end

  for _, bufnr in ipairs(touched_bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.fn.buflisted(bufnr) ~= 1 then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    else
      clear_hl(bufnr)
    end
  end
  touched_bufs = {}
end

function Preview:hl_buf(item)
  for row = item.start.line, item.finish.line, 1 do
    local col_start = 0
    local col_end = -1

    if row == item.start.line then
      col_start = item.start.character
    end

    if row == item.finish.line then
      col_end = item.finish.character
    end

    local match_hl = vim.fn.has('nvim-0.8') == 1 and 'None' or 'PreviewMatch'

    vim.api.nvim_buf_add_highlight(
      item.bufnr,
      config.namespace,
      config.hl_ns .. match_hl,
      row,
      col_start,
      col_end
    )
  end
end

function Preview:update(item, group)
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  if not item or item.is_file or item.is_unreachable then
    return
  end

  if vim.deep_equal(self.current_location, item) then
    return
  end

  local current_bufnr = (self.current_location or {}).bufnr

  if current_bufnr ~= item.bufnr then
    self:restore_win_opts()
    self:on_detach_buffer()
    vim.api.nvim_win_set_buf(self.winnr, item.bufnr)
    utils.win_set_options(self.winnr, win_opts)

    if config.options.winbar.enable and self.winbar then
      local filename = vim.fn.fnamemodify(item.filename, ':t')
      local filepath = vim.fn.fnamemodify(item.filename, ':p:~:h')
      self.winbar:render({ filename = filename, filepath = filepath })
    end
  end

  vim.api.nvim_win_set_cursor(
    self.winnr,
    { item.start.line + 1, item.start.character }
  )

  vim.api.nvim_win_call(self.winnr, function()
    vim.cmd('norm! zv')
    vim.cmd('norm! zz')
  end)

  vim.api.nvim_buf_call(item.bufnr, function()
    if vim.api.nvim_buf_get_option(item.bufnr, 'filetype') == '' then
      vim.cmd('do BufRead')
    end
  end)

  self.current_location = item
  self:on_attach_buffer()

  if not vim.tbl_contains(touched_bufs, item.bufnr) then
    for _, location in pairs(group.items) do
      self:hl_buf(location)
    end
    table.insert(touched_bufs, item.bufnr)
  end
end

return Preview
