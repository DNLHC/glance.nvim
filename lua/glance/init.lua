local config = require('glance.config')
local highlights = require('glance.highlights')
local utils = require('glance.utils')
local lsp = require('glance.lsp')

local Glance = {}
local glance = {}
Glance.__index = Glance
local initialized = false
local last_session = nil

---@param opts? GlanceOpts
function Glance.setup(opts)
  if initialized then
    return
  end

  config.setup(opts, Glance.actions)
  highlights.setup()
  lsp.setup()

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

local function is_detached(winnr)
  local detached = config.options.detached
  if type(detached) == 'function' then
    return detached(winnr)
  end
  return detached
end

local function get_win_above(winnr)
  return vim.api.nvim_win_call(winnr, function()
    return vim.fn.win_getid(vim.fn.winnr('k'))
  end)
end

local function get_offset_top(winnr)
  local win_above = get_win_above(winnr)
  if winnr ~= win_above and not utils.is_float_win(win_above) then
    -- plus 1 for the border
    return vim.fn.winheight(win_above) + get_offset_top(win_above) + 1
  end
  return 0
end

local function get_win_opts(winnr, line)
  local opts = config.options
  local detached = is_detached(winnr)
  local win_width = detached and vim.o.columns or vim.fn.winwidth(winnr)
  local list_width =
    utils.round(win_width * math.min(0.5, math.max(0.1, opts.list.width)))
  local preview_width = win_width - list_width
  local height = get_preview_win_height(winnr)
  local list_pos = opts.list.position
  local row = line

  if detached then
    local winbar_space = vim.api.nvim_win_call(winnr, function()
      if vim.fn.has('nvim-0.8') ~= 0 then
        return vim.o.winbar ~= '' and 1 or 0
      end
      return 0
    end)

    local tabline_space = vim.api.nvim_win_call(winnr, function()
      return vim.o.tabline ~= '' and 1 or 0
    end)

    local offset = get_offset_top(winnr)
    row = offset + line + winbar_space + tabline_space
  end

  local win_opts = {
    relative = detached and 'editor' or 'win',
    height = height,
    win = (not detached) and winnr or nil,
    zindex = opts.zindex,
    row = row,
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

local function create(
  results,
  parent_bufnr,
  parent_winnr,
  params,
  method,
  offset_encoding
)
  glance = Glance:create({
    bufnr = parent_bufnr,
    winnr = parent_winnr,
    params = params,
    results = results,
    method = method,
    offset_encoding = offset_encoding,
  })

  local augroup = vim.api.nvim_create_augroup('Glance', { clear = true })

  -- cleanup autocommand which ensures if the user navigates away from Glance,
  -- by either jumping out of the preview or list, or by changing the buffer
  -- in the preview or list windows, we gracefully close.
  Glance.cleanup = vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
    group = augroup,
    callback = function()
      local cur_win = vim.api.nvim_get_current_win()
      local cur_buf = vim.api.nvim_get_current_buf()

      -- we allow the preview to change buffers, this allows nested glance
      -- calls
      local left_preview = cur_win ~= glance.preview.winnr
      local left_list = (
        cur_buf ~= glance.list.bufnr or cur_win ~= glance.list.winnr
      )

      if left_preview and left_list then
        vim.api.nvim_del_autocmd(Glance.cleanup)
        Glance.cleanup = 0
        Glance.actions.close()
      end
    end,
  })

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

---@class GlanceOpenOpts
---@field method GlanceMethod
---@field hooks? GlanceHooksOpts

---@param opts GlanceOpenOpts
local function open(opts)
  local parent_bufnr = vim.api.nvim_get_current_buf()
  local parent_winnr = vim.api.nvim_get_current_win()
  local params = vim.lsp.util.make_position_params()

  lsp.request(opts.method, params, parent_bufnr, function(results, ctx)
    if vim.tbl_isempty(results) then
      return utils.info(('No %s found'):format(lsp.methods[opts.method].label))
    end

    local client = vim.lsp.get_client_by_id(ctx.client_id)

    if is_open() then
      glance.list:setup({
        results = results,
        position_params = params,
        method = opts.method,
        offset_encoding = client.offset_encoding,
      })
      glance.preview:clear_hl()
      glance:update_preview(glance.list:get_current_item())
      vim.api.nvim_set_current_win(glance.list.winnr)
    else
      local _open = function(_results)
        _results = _results or results
        create(
          _results,
          parent_bufnr,
          parent_winnr,
          params,
          opts.method,
          client.offset_encoding
        )
      end

      local _jump = function(result)
        result = result or results[1]
        vim.lsp.util.jump_to_location(result, client.offset_encoding)
      end

      local hooks = opts.hooks or config.options.hooks

      if hooks and type(hooks.before_open) == 'function' then
        hooks.before_open(results, _open, _jump, opts.method)
      else
        _open()
      end
    end
  end)
end

---@class GlanceActions
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
    local item = glance.list:next({ skip_groups = true, cycle = true })
    glance:update_preview(item)
  end,
  previous_location = function()
    local item = glance.list:previous({ skip_groups = true, cycle = true })
    glance:update_preview(item)
  end,
  preview_scroll_win = function(distance)
    vim.validate({
      distance = {
        distance,
        function(v)
          return type(v) == 'number' and v ~= 0
        end,
        'valid number',
      },
    })

    return function()
      local cmd = distance > 0 and [[\<C-y>]] or [[\<C-e>]]
      vim.api.nvim_win_call(glance.preview.winnr, function()
        vim.cmd(('exec "norm! %d%s"'):format(math.abs(distance), cmd))
      end)
    end
  end,
  jump = function(opts)
    glance:jump(opts)
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
  ---@param method GlanceMethod
  ---@param opts? { hooks: GlanceHooks }
  open = function(method, opts)
    local commands = vim.tbl_keys(require('glance.lsp').methods)
    table.insert(commands, 'resume')
    vim.validate({
      method = utils.valid_enum(method, commands, false),
    })
    -- Manually call the setup in case user hasn't initialized the plugin
    -- It will only run once
    Glance.setup()
    open({ method = method, hooks = opts and opts.hooks })
  end,
  quickfix = function()
    local qf_items = {}
    for _, group in pairs(glance.list.groups) do
      for _, item in ipairs(group.items) do
        table.insert(qf_items, {
          bufnr = item.bufnr,
          filename = item.filename,
          lnum = item.start_line + 1,
          end_lnum = item.end_line + 1,
          col = item.start_col + 1,
          end_col = item.end_col + 1,
          text = item.full_text,
        })
      end
    end
    vim.fn.setqflist(qf_items, 'r')
    Glance.actions.close()
    if config.options.use_trouble_qf and pcall(require, 'trouble') then
      require('trouble').open('quickfix')
    else
      vim.cmd.copen()
    end
  end,
  toggle_fold = function()
    glance:toggle_fold()
  end,
  open_fold = function()
    glance:toggle_fold(true)
  end,
  close_fold = function()
    glance:toggle_fold(false)
  end,
  resume = function()
    if not last_session then
      return utils.info('No previous Glance session to resume')
    end

    -- Create new Glance instance with stored state
    create(
      last_session.results,
      vim.api.nvim_get_current_buf(),
      vim.api.nvim_get_current_win(),
      vim.lsp.util.make_position_params(),
      last_session.method,
      last_session.offset_encoding
    )

    -- TODO: Restore cursor position
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
    offset_encoding = opts.offset_encoding,
  })

  local preview = require('glance.preview').create({
    parent_winnr = opts.winnr,
    parent_bufnr = opts.bufnr,
    win_opts = preview_win_opts,
    preview_bufnr = list:get_current_item().bufnr,
  })

  -- Used for restoring the previous session
  last_session = {
    results = opts.results,
    position_params = opts.params,
    method = opts.method,
    offset_encoding = opts.offset_encoding,
  }

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

  local scrolloff_value = vim.wo.scrolloff
  vim.wo.scrolloff = 0

  -- Scroll the window down until we have enough rows to render the preview window.
  -- Needs to be done row by row because the <C-e> command scrolls over lines and not rows
  -- some lines can take more than 1 row when 'wrap' is enabled
  -- which makes it hard to calculate the scroll distance beforehand.
  while win_height - row < preview_height do
    vim.cmd([[exec "norm! \<C-e>"]])
    row = vim.fn.winline()
  end

  vim.wo.scrolloff = scrolloff_value

  return row
end

function Glance:jump(opts)
  opts = opts or {}

  local current_item = self.list:get_current_item()

  if not current_item or current_item.is_unreachable then
    return
  end

  if current_item.is_group then
    return self.list:toggle_fold(current_item)
  end

  self:close()

  glance.push_tagstack()

  if opts.cmd then
    if type(opts.cmd) == 'function' then
      opts.cmd(current_item)
    else
      vim.cmd(opts.cmd)
    end
  end

  if vim.fn.buflisted(current_item.bufnr) == 1 then
    vim.cmd(('buffer %s'):format(current_item.bufnr))
  else
    vim.cmd(('edit %s'):format(vim.fn.fnameescape(current_item.filename)))
  end

  vim.api.nvim_win_set_cursor(
    0,
    { current_item.start_line + 1, current_item.start_col }
  )
  vim.cmd('norm! zz')

  self:destroy()
end

function Glance:toggle_fold(expand)
  local item = self.list:get_current_item()

  if not item or self.list:is_flat() then
    return
  end

  if expand == nil then
    return self.list:toggle_fold(item)
  elseif expand then
    return self.list:open_fold(item)
  end

  return self.list:close_fold(item)
end

function Glance:update_preview(item)
  if item and not item.is_group then
    local group = self.list:get_active_group({ location = item })
    self.preview:update(item, group)
  end
end

function Glance:close()
  local hooks = config.options.hooks or {}

  if type(hooks.before_close) == 'function' then
    hooks.before_close()
  end

  if self.cleanup > 0 then
    vim.api.nvim_del_autocmd(self.cleanup)
  end

  if vim.api.nvim_win_is_valid(self.parent_winnr) then
    vim.api.nvim_set_current_win(self.parent_winnr)
  end

  vim.api.nvim_del_augroup_by_name('Glance')

  self.list:close()
  self.preview:close()

  if type(hooks.after_close) == 'function' then
    vim.schedule(hooks.after_close)
  end
end

function Glance:destroy()
  self.list:destroy()
  self.preview:destroy()
  glance = {}
end

Glance.register_method = function(method)
  vim.validate({
    name = { method.name, 'string' },
    label = { method.label, 'string' },
    method = { method.method, 'string' },
  })

  if lsp.methods[method.name] then
    return utils.error(("method '%s' already registered"):format(method.name))
  end

  lsp.methods[method.name] = {
    label = method.label,
    lsp_method = method.method,
    non_standard = true,
  }
end

Glance.open = Glance.actions.open

Glance.is_open = is_open

return Glance
