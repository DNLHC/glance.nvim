local config = require('glance.config')
local highlights = require('glance.highlights')
local utils = require('glance.utils')

local Glance = {}
local glance = {}
Glance.__index = Glance
local initialized = false
local is_fetching = false

function Glance.setup(opts)
  if initialized then
    return
  end

  config.setup(opts, Glance.actions)
  highlights.setup()

  initialized = true
end

local function get_border_opts(win)
  local border_opts = config.options.border
  local border_bottom_hl = ('Glance%sBorderBottom'):format(
    utils.capitalize(win)
  )
  return border_opts.enable
      and {
        '',
        { border_opts.top_char, 'GlanceBorderTop' },
        '',
        '',
        '',
        { border_opts.bottom_char, border_bottom_hl },
        '',
        '',
      }
    or 'none'
end

local function is_open()
  if vim.tbl_isempty(glance) then
    return false
  end

  local preview_is_valid = glance.preview and glance.preview:is_valid()
  local list_is_valid = glance.list and glance.list:is_valid()
  return list_is_valid and preview_is_valid
end

local function get_preview_win_height(winnr)
  return math.min(vim.fn.winheight(winnr), config.options.height)
end

local function get_win_opts(winnr, line)
  local win_width = vim.fn.winwidth(winnr)
  local list_width = utils.round(
    win_width * math.min(0.5, math.max(0.1, config.options.list.width))
  )
  local preview_width = win_width - list_width
  local height = get_preview_win_height(winnr)
  local list_pos = config.options.list.position
  local win_opts = {
    relative = 'win',
    height = height,
    win = winnr,
    zindex = config.options.zindex,
    row = line,
  }

  local list_win_opts = vim.tbl_extend('keep', {
    width = list_width,
    col = list_pos == 'left' and 0 or preview_width,
    style = 'minimal',
    border = get_border_opts('list'),
  }, win_opts)

  local preview_win_opts = vim.tbl_extend('keep', {
    width = preview_width,
    col = list_pos == 'left' and list_width or 0,
    border = get_border_opts('preview'),
  }, win_opts)

  return list_win_opts, preview_win_opts
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
      tostring(parent_winnr),
    },
    callback = function()
      Glance.actions.close()
    end,
  })

  local debounced_on_resize = utils.debounce(function()
    if is_open() then
      glance:on_resize()
    end
  end, 50)

  vim.api.nvim_create_autocmd('WinScrolled', {
    group = augroup,
    callback = function(event)
      if not utils.is_float_win(tonumber(event.match)) then
        debounced_on_resize()
      end
    end,
  })
end

local function open(opts)
  if is_fetching then
    return
  end

  is_fetching = true
  local lsp = require('glance.lsp')
  local parent_bufnr = vim.api.nvim_get_current_buf()
  local parent_winnr = vim.api.nvim_get_current_win()
  local params = vim.lsp.util.make_position_params()

  lsp.request(opts.method, params, parent_bufnr, function(results, ctx)
    is_fetching = false

    if vim.tbl_isempty(results) then
      return utils.info(('No %s found'):format(lsp.methods[opts.method].label))
    end

    if is_open() then
      glance.list:setup({
        results = results,
        position_params = params,
        method = opts.method,
      })
      glance:update_preview(glance.list:get_current_item())
      vim.api.nvim_set_current_win(glance.list.winnr)
    else
      local _open = function(_results)
        _results = _results or results
        create(_results, parent_bufnr, parent_winnr, params, opts.method)
      end

      local _jump = function(result)
        result = result or results[1]
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        vim.lsp.util.jump_to_location(result, client.offset_encoding)
      end

      local hooks = config.options.hooks

      if hooks and type(hooks.before_open) == 'function' then
        hooks.before_open(results, _open, _jump, opts.method)
      else
        _open()
      end
    end
  end)
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
    local item = glance.list:next({ loc_only = true, cycle = true })
    glance:update_preview(item)
  end,
  previous_location = function()
    local item = glance.list:previous({ loc_only = true, cycle = true })
    glance:update_preview(item)
  end,
  preview_scroll_win = function(distance)
    return function()
      local cmd = distance > 0 and [[\<C-y>]] or [[\<C-e>]]
      vim.api.nvim_win_call(glance.preview.winnr, function()
        vim.cmd(('exec "norm! %d%s"'):format(math.abs(distance), cmd))
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
    open({ method = method })
  end,
}

function Glance:create(opts)
  local row = self:scroll_into_view(opts.winnr, opts.params.position)
  local push_tagstack = utils.create_push_tagstack(opts.winnr)
  local list_win_opts, preview_win_opts = get_win_opts(opts.winnr, row)

  local list = require('glance.list').create({
    results = opts.results,
    parent_winnr = opts.winnr,
    position_params = opts.params,
    method = opts.method,
    win_opts = list_win_opts,
  })

  local preview = require('glance.preview').create({
    parent_winnr = opts.winnr,
    parent_bufnr = opts.bufnr,
    win_opts = preview_win_opts,
    preview_bufnr = list:get_current_item().bufnr,
  })

  local scope = {
    list = list,
    preview = preview,
    push_tagstack = push_tagstack,
    parent_winnr = opts.winnr,
    parent_bufnr = opts.bufnr,
    row = row,
  }

  setmetatable(scope, self)
  return scope
end

function Glance:on_resize()
  local list_win_opts, preview_win_opts =
    get_win_opts(self.parent_winnr, self.row)
  vim.api.nvim_win_set_config(self.list.winnr, list_win_opts)
  vim.api.nvim_win_set_config(self.preview.winnr, preview_win_opts)
end

function Glance:scroll_into_view(winnr, position)
  -- User might have moved cursor during the lsp request
  -- Set the cursor position just in case
  vim.api.nvim_win_set_cursor(winnr, { position.line + 1, position.character })
  local win_height = vim.fn.winheight(winnr)
  local row = vim.fn.winline()
  local bottom_offset = 2
  local border_height = config.options.border.enable and 2 or 0
  local preview_height = get_preview_win_height(winnr)
    + border_height
    + bottom_offset

  if preview_height >= win_height then
    return 0
  end

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

  if not current_item or current_item.is_unreachable then
    return
  end

  if current_item.is_file then
    return self.list:toggle_fold(current_item)
  end

  self:close()

  glance.push_tagstack()

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
  local hooks = config.options.hooks

  if hooks and type(hooks.before_close) == 'function' then
    hooks.before_close()
  end

  if vim.api.nvim_win_is_valid(self.parent_winnr) then
    vim.api.nvim_set_current_win(self.parent_winnr)
  end
  vim.api.nvim_del_augroup_by_name('Glance')
  self.list:close()
  self.preview:close()

  if hooks and type(hooks.after_close) == 'function' then
    vim.schedule(hooks.after_close)
  end
end

function Glance:destroy()
  self.list:destroy()
  self.preview:destroy()
  glance = {}
end

Glance.open = Glance.actions.open

return Glance
