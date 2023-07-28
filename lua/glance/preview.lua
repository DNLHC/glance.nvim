local config = require('glance.config')
local utils = require('glance.utils')
local Winbar = require('glance.winbar')

local Preview = {}
Preview.__index = Preview

local touched_buffers = {}

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
  cursorbind = false,
  scrollbind = false,
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
  win_opts =
    vim.tbl_extend('keep', win_opts, config.options.preview_win_opts or {})
  local preview = Preview:new(opts)
  return preview
end

function Preview:new(opts)
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

function Preview:on_attach_buffer(bufnr)
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    local throttled_on_change, on_change_timer = utils.throttle_leading(
      function()
        local is_active_buffer = self.current_location
          and bufnr == self.current_location.bufnr
        local is_listed = vim.fn.buflisted(bufnr) == 1

        if is_active_buffer and not is_listed then
          vim.api.nvim_buf_set_option(bufnr, 'buflisted', true)
          vim.api.nvim_buf_set_option(bufnr, 'bufhidden', '')
        end
      end,
      1000
    )

    local autocmd_id = vim.api.nvim_create_autocmd(
      { 'TextChanged', 'TextChangedI' },
      {
        group = 'Glance',
        buffer = bufnr,
        callback = throttled_on_change,
      }
    )

    self.clear_autocmd = function()
      pcall(vim.api.nvim_del_autocmd, autocmd_id)
      if on_change_timer then
        on_change_timer:close()
        on_change_timer = nil
      end
    end

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

function Preview:on_detach_buffer(bufnr)
  if type(self.clear_autocmd) == 'function' then
    self.clear_autocmd()
    self.clear_autocmd = nil
  end

  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    for lhs, _ in pairs(config.options.mappings.preview) do
      pcall(vim.api.nvim_buf_del_keymap, bufnr, 'n', lhs)
    end
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
  self:on_detach_buffer((self.current_location or {}).bufnr)
  self:restore_win_opts()

  if vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_win_close(self.winnr, {})
  end

  for _, bufnr in ipairs(touched_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.fn.buflisted(bufnr) ~= 1 then
      if
        vim.fn.has('nvim-0.9.2') == 1
        and type(vim.lsp.inlay_hint) == 'function'
      then
        vim.lsp.inlay_hint(bufnr, false)
      end
      vim.api.nvim_buf_delete(bufnr, { force = true })
    else
      clear_hl(bufnr)
    end
  end

  touched_buffers = {}
end

function Preview:clear_hl()
  for _, bufnr in ipairs(touched_buffers) do
    clear_hl(bufnr)
  end
  touched_buffers = {}
end

function Preview:hl_buf(location)
  for row = location.start_line, location.end_line, 1 do
    local start_col = 0
    local end_col = -1

    if row == location.start_line then
      start_col = location.start_col
    end

    if row == location.end_line then
      end_col = location.end_col
    end

    local match_hl = vim.fn.has('nvim-0.8') == 1 and 'None' or 'PreviewMatch'

    vim.api.nvim_buf_add_highlight(
      location.bufnr,
      config.namespace,
      config.hl_ns .. match_hl,
      row,
      start_col,
      end_col
    )
  end
end

function Preview:update(item, group)
  if not vim.api.nvim_win_is_valid(self.winnr) then
    return
  end

  if not item or item.is_group or item.is_unreachable then
    return
  end

  if vim.deep_equal(self.current_location, item) then
    return
  end

  local current_bufnr = (self.current_location or {}).bufnr

  if current_bufnr ~= item.bufnr then
    self:restore_win_opts()
    self:on_detach_buffer(current_bufnr)
    vim.api.nvim_win_set_buf(self.winnr, item.bufnr)
    utils.win_set_options(self.winnr, win_opts)

    if config.options.winbar.enable and self.winbar then
      local filename = vim.fn.fnamemodify(item.filename, ':t')
      local filepath = vim.fn.fnamemodify(item.filename, ':p:~:h')
      self.winbar:render({ filename = filename, filepath = filepath })
    end

    vim.api.nvim_buf_call(item.bufnr, function()
      if vim.api.nvim_buf_get_option(item.bufnr, 'filetype') == '' then
        vim.cmd('do BufRead')
      end
    end)

    self:on_attach_buffer(item.bufnr)
  end

  vim.api.nvim_win_set_cursor(
    self.winnr,
    { item.start_line + 1, item.start_col }
  )

  vim.api.nvim_win_call(self.winnr, function()
    vim.cmd('norm! zv')
    vim.cmd('norm! zz')
  end)

  self.current_location = item

  if not vim.tbl_contains(touched_buffers, item.bufnr) then
    for _, location in pairs(group.items) do
      self:hl_buf(location)
    end
    table.insert(touched_buffers, item.bufnr)
  end
end

return Preview
