local config = require('glance.config')
local highlights = require('glance.highlights')
local utils = require('glance.utils')

local Glance = {}
local glance = {}
Glance.__index = Glance
local initialized = false

function Glance.setup(opts)
  if initialized then
    return
  end

  config.setup(opts, Glance.actions)
  highlights.setup()

  initialized = true
end

local function create(results, parent_bufnr, parent_winnr, params, method)
  glance = Glance:create({
    bufnr = parent_bufnr,
    winnr = parent_winnr,
    params = params,
    results = results,
    method = method,
  })

  local augroup = vim.api.nvim_create_augroup('Glance', { clear = true })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = augroup,
    buffer = glance.list.bufnr,
    callback = function()
      glance:update_preview(glance.list:get_current_item())
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    pattern = {
      tostring(glance.list.winnr),
      tostring(glance.preview.winnr),
    },
    callback = function()
      Glance.actions.close()
    end,
  })
end

local function open(opts)
  local parent_bufnr = vim.api.nvim_get_current_buf()
  local parent_winnr = vim.api.nvim_get_current_win()
  local params = vim.lsp.util.make_position_params()

  require('glance.lsp').request(
    opts.method,
    params,
    parent_bufnr,
    function(results)
      if vim.tbl_isempty(results) then
        return
      end

      local _open = function(_results)
        _results = _results or results
        create(_results, parent_bufnr, parent_winnr, params, opts.method)
      end

      local _jump = function(result)
        result = result or results[1]
        vim.lsp.util.jump_to_location(result, 'utf-8')
      end

      local hooks = config.options.hooks

      if type(hooks.before_open) == 'function' then
        hooks.before_open(results, _open, _jump, opts.method)
      else
        _open()
      end
    end
  )
end

local function is_open()
  local preview_is_valid = glance.preview and glance.preview:is_valid()
  local list_is_valid = glance.list and glance.list:is_valid()
  return list_is_valid and preview_is_valid
end

Glance.actions = {
  close = function()
    glance:close()
    glance:destroy()
  end,
  enter_win = function(win)
    vim.validate({
      win = utils.valid_enum(win, { 'preview', 'list' }, false),
    })
    return function()
      if not is_open() then
        return
      end

      if win == 'preview' then
        vim.api.nvim_set_current_win(glance.preview.winnr)
      end

      if win == 'list' then
        vim.api.nvim_set_current_win(glance.list.winnr)
      end
    end
  end,
  next = function()
    local item = glance.list:next()
    glance:update_preview(item)
  end,
  previous = function()
    local item = glance.list:previous()
    glance:update_preview(item)
  end,
  next_location = function()
    local item = glance.list:next({ loc_only = true })
    glance:update_preview(item)
  end,
  previous_location = function()
    local item = glance.list:previous({ loc_only = true })
    glance:update_preview(item)
  end,
  preview_scroll_win = function(distance)
    return function()
      local cmd = distance > 0 and [[\<C-y>]] or [[\<C-e>]]
      vim.api.nvim_win_call(glance.preview.winnr, function()
        vim.cmd(('exec "norm! %d%s"'):format(distance, cmd))
      end)
    end
  end,
  jump = function()
    glance:jump()
  end,
  jump_vsplit = function()
    glance:jump({ cmd = 'vsplit' })
  end,
  jump_tab = function()
    glance:jump({ cmd = 'tabe' })
  end,
  jump_split = function()
    glance:jump({ cmd = 'split' })
  end,
  open = function(method)
    vim.validate({
      method = utils.valid_enum(
        method,
        vim.tbl_keys(require('glance.lsp').methods),
        false
      ),
    })
    if is_open() then
      Glance.actions.close()
    end
    open({ method = method })
  end,
}

function Glance:create(opts)
  local row = self:scroll_into_view(opts.winnr, opts.params.position)
  local list_width = utils.round(
    vim.fn.winwidth(opts.winnr)
      * math.min(0.5, math.max(0.1, config.options.list.width))
  )

  local push_tagstack = utils.create_push_tagstack(opts.winnr)

  local list = require('glance.list').create({
    results = opts.results,
    parent_winnr = opts.winnr,
    uri = opts.params.textDocument.uri,
    pos = opts.params.position,
    method = opts.method,
    row = row,
    list_width = list_width,
  })
  local preview = require('glance.preview').create({
    parent_winnr = opts.winnr,
    parent_bufnr = opts.bufnr,
    row = row,
    list_width = list_width,
    preview_bufnr = list:get_current_item().bufnr,
  })

  local scope = {
    list = list,
    preview = preview,
    push_tagstack = push_tagstack,
    parent_winnr = opts.winnr,
    parent_bufnr = opts.bufnr,
  }

  setmetatable(scope, self)
  return scope
end

function Glance:scroll_into_view(winnr, position)
  -- User might have moved cursor during the lsp request
  -- Set the cursor position just in case
  vim.api.nvim_win_set_cursor(winnr, { position.line + 1, position.character })
  local win_height = vim.fn.winheight(winnr)
  local row = vim.fn.winline()
  local bottom_offset = 2
  local border_height = config.options.border.enable and 2 or 0
  local preview_height = config.options.height + border_height + bottom_offset

  -- Scroll the window down until we have enough rows to render the preview window.
  -- Needs to be done row by row because the <C-e> command scrolls over lines and not rows
  -- some lines can take more than 1 row when 'wrap' is enabled
  -- which makes it hard to calculate the scroll distance beforehand.
  while win_height - row < preview_height do
    vim.cmd([[exec "norm! \<C-e>"]])
    row = vim.fn.winline()
  end

  return row
end

function Glance:jump(opts)
  opts = opts or {}

  local current_item = self.list:get_current_item()

  if not current_item then
    return
  end

  if current_item.is_file then
    return self.list:toggle_fold(current_item)
  end

  self:close()

  if opts.cmd then
    vim.cmd(opts.cmd)
  end

  if vim.fn.buflisted(current_item.bufnr) == 1 then
    vim.cmd(('buffer %s'):format(current_item.bufnr))
  else
    vim.cmd(('edit %s'):format(vim.fn.fnameescape(current_item.filename)))
  end

  vim.api.nvim_win_set_cursor(
    0,
    { current_item.start.line + 1, current_item.start.character }
  )
  vim.cmd('norm! zz')

  self:destroy()
end

function Glance:update_preview(item)
  if item and not item.is_file then
    local group = self.list:get_active_group({ location = item })
    self.preview:update(item, group)
  end
end

function Glance:close()
  vim.api.nvim_del_augroup_by_name('Glance')
  self.list:close()
  self.preview:close()
end

function Glance:destroy()
  self.list:destroy()
  self.preview:destroy()
  glance = {}
end

Glance.open = Glance.actions.open

return Glance
