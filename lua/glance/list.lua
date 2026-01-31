local Renderer = require('glance.renderer')
local Winbar = require('glance.winbar')
local lsp = require('glance.lsp')
local Range = require('glance.range')
local folds = require('glance.folds')
local config = require('glance.config')
local utils = require('glance.utils')
local List = {}
List.__index = List

local winhl = {
  'Normal:GlanceListNormal',
  'CursorLine:GlanceListCursorLine',
  'EndOfBuffer:GlanceListEndOfBuffer',
}

local win_opts = {
  winfixwidth = true,
  winfixheight = true,
  cursorline = true,
  wrap = false,
  signcolumn = 'no',
  foldenable = false,
  winhighlight = table.concat(winhl, ','),
}

local buf_opts = {
  bufhidden = 'wipe',
  buftype = 'nofile',
  swapfile = false,
  buflisted = false,
  filetype = 'Glance',
}

function List.create(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winnr = vim.api.nvim_open_win(bufnr, true, opts.win_opts)

  local list = List:new(bufnr, winnr)
  utils.win_set_options(winnr, win_opts)
  utils.buf_set_options(bufnr, buf_opts)
  list:setup(opts)
  list:set_keymaps()

  return list
end

function List:new(bufnr, winnr)
  local scope = {
    bufnr = bufnr,
    winnr = winnr,
    items = {},
    groups = {},
    winbar = nil,
  }

  if config.options.winbar.enable then
    local winbar = Winbar:new(winnr)
    winbar:append('title', 'WinBarTitle')
    scope.winbar = winbar
  end

  setmetatable(scope, self)
  return scope
end

function List:set_keymaps()
  local mappings = config.options.mappings

  local keymap_opts = {
    buffer = self.bufnr,
    noremap = true,
    nowait = true,
    silent = true,
  }

  for key, action in pairs(mappings.list) do
    vim.keymap.set('n', key, action, keymap_opts)
  end
end

function List:is_valid()
  return self.winnr and vim.api.nvim_win_is_valid(self.winnr)
end

local function find_location_position(items, location)
  return utils.tbl_find(items, function(item)
    return vim.deep_equal(item, location)
  end)
end

local function find_starting_location(locations)
  return utils.tbl_find(locations, function(location)
    return location.is_starting
  end)
end

local function find_starting_group_and_location(groups, position_params)
  local fallback = nil
  for _, group in pairs(groups) do
    local starting_location = find_starting_location(group.items)

    if starting_location then
      return group, starting_location
    end

    if not fallback and position_params.textDocument.uri == group.uri then
      fallback = { group = group, location = group.items[1] }
    end
  end

  if fallback then
    return fallback.group, fallback.location
  end

  -- if nothing was found return the first group and location
  local _, group = next(groups)
  return group, group.items[1]
end

local function is_starting_location(
  position_params,
  location_uri,
  location_range
)
  if location_uri ~= position_params.textDocument.uri then
    return false
  end

  local range = Range:new(
    location_range.start.line,
    location_range.start.character,
    location_range.finish.line,
    location_range.finish.character
  )

  return range:contains_position({
    line = position_params.position.line,
    col = position_params.position.character,
  })
end

local function get_preview_line(range, offset, text)
  local word = utils.get_word_until_position(range.start_col - offset, text)

  if range.end_line > range.start_line then
    range.end_col = string.len(text) + 1
  end

  local before = utils
    .get_value_in_range(word.start_col, range.start_col, text)
    :gsub('^%s+', '')
  local inside = utils.get_value_in_range(range.start_col, range.end_col, text)
  local after = utils
    .get_value_in_range(range.end_col, string.len(text) + 1, text)
    :gsub('%s+$', '')

  return {
    value = {
      before = before,
      inside = inside,
      after = after,
    },
  }
end

---@private
--- from: https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/util.lua
--- Gets the zero-indexed lines from the given buffer.
--- Works on unloaded buffers by reading the file using libuv to bypass buf reading events.
--- Falls back to loading the buffer and nvim_buf_get_lines for buffers with non-file URI.
---
---@param bufnr number bufnr to get the lines from
---@param rows number[] zero-indexed line numbers
---@return table<number, string> | nil a table mapping rows to lines
local function get_lines(bufnr, uri, rows)
  rows = type(rows) == 'table' and rows or { rows }

  -- This is needed for bufload and bufloaded
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  ---@private
  local function buf_lines()
    local lines = {}
    for _, row in pairs(rows) do
      lines[row] = (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false) or {
        '',
      })[1]
    end
    return lines
  end

  -- load the buffer if this is not a file uri
  -- Custom language server protocol extensions can result in servers sending URIs with custom schemes. Plugins are able to load these via `BufReadCmd` autocmds.
  if uri:sub(1, 4) ~= 'file' then
    vim.fn.bufload(bufnr)
    return buf_lines()
  end

  -- use loaded buffers if available
  if vim.fn.bufloaded(bufnr) == 1 then
    return buf_lines()
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)

  -- get the data from the file
  local fd = vim.loop.fs_open(filename, 'r', 438)

  if not fd then
    return nil
  end

  local stat = vim.loop.fs_fstat(fd)
  local data = vim.loop.fs_read(fd, stat.size, 0)
  vim.loop.fs_close(fd)

  local lines = {} -- rows we need to retrieve
  local rows_needed = 0 -- keep track of how many unique rows we need
  for _, row in pairs(rows) do
    if not lines[row] then
      rows_needed = rows_needed + 1
    end
    lines[row] = true
  end

  local found = 0
  local lnum = 0

  for line in string.gmatch(data, '([^\n]*)\n?') do
    if lines[lnum] == true then
      lines[lnum] = line
      found = found + 1
      if found == rows_needed then
        break
      end
    end
    lnum = lnum + 1
  end

  -- change any lines we didn't find to the empty string
  for i, line in pairs(lines) do
    if line == true then
      lines[i] = ''
    end
  end
  return lines
end

local function sort_by_key(fn)
  return function(a, b)
    local ka, kb = fn(a), fn(b)
    assert(#ka == #kb)
    for i = 1, #ka do
      if ka[i] ~= kb[i] then
        return ka[i] < kb[i]
      end
    end
    -- every value must have been equal here, which means it's not less than.
    return false
  end
end

local position_sort = sort_by_key(function(v)
  return { v.start.line, v.start.character }
end)

local function process_locations(locations, position_params, offset_encoding)
  local result = {}

  local grouped = setmetatable({}, {
    __index = function(t, k)
      local v = {}
      rawset(t, k, v)
      return v
    end,
  })

  for _, location in ipairs(locations) do
    local uri = location.uri or location.targetUri
    local range = location.range or location.targetSelectionRange
    table.insert(grouped[uri], { start = range.start, finish = range['end'], src = location })
  end

  local keys = vim.tbl_keys(grouped)
  table.sort(keys)

  for _, uri in ipairs(keys) do
    local rows = grouped[uri]
    table.sort(rows, position_sort)
    local filename = vim.uri_to_fname(uri)
    local bufnr = vim.uri_to_bufnr(uri)
    result[filename] = {
      filename = filename,
      uri = uri,
      items = {},
    }

    -- list of row numbers
    local uri_rows = {}

    for _, position in ipairs(rows) do
      local row = position.start.line
      table.insert(uri_rows, row)
    end

    -- get all the lines for this uri
    local lines = get_lines(bufnr, uri, uri_rows)

    for index, position in ipairs(rows) do
      local preview_line
      local is_unreachable = false
      local start = position.start
      local finish = position.finish
      local src = position.src
      local start_col = start.character
      local end_col = finish.character
      local row = start.line
      local line = lines and lines[row]

      if not line then
        line = ('%s:%d:%d'):format(
          vim.fn.fnamemodify(filename, ':t'),
          start_col + 1,
          end_col + 1
        )
        is_unreachable = true
      else
        start_col =
          utils.get_line_byte_from_position(line, start, offset_encoding)
        end_col =
          utils.get_line_byte_from_position(line, finish, offset_encoding)

        preview_line = get_preview_line({
          start_line = row,
          start_col = start_col,
          end_col = end_col,
          end_line = finish.line,
        }, 8, line)
      end

      local location = {
        filename = filename,
        bufnr = bufnr,
        index = index,
        uri = uri,
        preview_line = preview_line,
        is_unreachable = is_unreachable,
        full_text = line or '',
        start_line = start.line,
        end_line = finish.line,
        start_col = start_col,
        end_col = end_col,
        is_starting = is_starting_location(
          position_params,
          uri,
          { start = start, finish = finish }
        ),
        -- depth for nested rendering (top-level items start at 0)
        depth = 0,
        -- preserve any call metadata returned by the LSP handler
        call = src and src.call or nil,
        call_item = src and src.call_item or nil,
      }

      table.insert(result[filename].items, location)
    end
  end

  return result
end

local function get_lsp_method_label(method_name)
  return utils.capitalize(lsp.methods[method_name].label)
end

function List:setup(opts)
  self.parent_bufnr = opts.parent_bufnr
  self.method = opts.method
  self.offset_encoding = opts.offset_encoding

  self.groups =
    process_locations(opts.results, opts.position_params, opts.offset_encoding)
  local group, location =
    find_starting_group_and_location(self.groups, opts.position_params)

  folds.reset()
  folds.open(group.filename)

  self:update(self.groups)
  local _, location_line = find_location_position(self.items, location)

  if config.options.winbar.enable and self.winbar then
    self.winbar:render({
      title = string.format(
        '%s (%d)',
        get_lsp_method_label(opts.method),
        #opts.results
      ),
    })
  end

  vim.api.nvim_win_set_cursor(self.winnr, { location_line, 1 })
  vim.schedule(function()
    vim.cmd('norm! zz')
  end)
end

function List:update(groups)
  utils.buf_set_options(self.bufnr, { modifiable = true, readonly = false })
  self:render(groups)
  utils.buf_set_options(self.bufnr, { modifiable = false, readonly = true })
end

function List:close()
  if vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_win_close(self.winnr, {})
  end

  if vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, {})
  end

  folds.reset()
end

function List:destroy()
  self.winnr = nil
  self.bufnr = nil
  self.items = nil
  self.groups = nil
  self.winbar = nil
end

function List:render(groups)
  local renderer = Renderer:new(self.bufnr)
  local icons = config.options.folds
  -- For call-hierarchy methods, render a single flattened list of locations
  -- (call relationships are represented via nested folds) instead of file groups.
  if self.method == 'incoming_calls' or self.method == 'outgoing_calls' then
    local combined = { items = {} }
    for _, group in pairs(groups) do
      for _, item in ipairs(group.items) do
        table.insert(combined.items, item)
      end
    end
    self:render_locations(combined.items, renderer, true)
  else
    if vim.tbl_count(groups) > 1 then
      for filename, group in pairs(groups) do
        self.items[renderer.line_nr + 1] = {
          filename = filename,
          uri = group.uri,
          is_group = true,
          count = #group.items,
        }

        local is_folded = folds.is_folded(filename)
        local fold_icon = is_folded and icons.fold_closed or icons.fold_open

        renderer:append(string.format(' %s ', fold_icon), 'FoldIcon')
        renderer:append(vim.fn.fnamemodify(filename, ':t'), 'ListFilename', ' ')
        renderer:append(
          vim.fn.fnamemodify(filename, ':p:.:h'),
          'ListFilepath',
          ' '
        )
        renderer:append(string.format(' %d ', #group.items), 'ListCount', ' ')
        renderer:nl()

        if not is_folded then
          self:render_locations(group.items, renderer, true)
        end
      end
    else
      local _, group = next(groups)
      self:render_locations(group.items, renderer, false)
    end
  end

  renderer:render()
  renderer:highlight()
end

function List:render_locations(locations, renderer, render_indent_line)
  local opts = config.options

  for _, location in ipairs(locations) do
    self.items[renderer.line_nr + 1] = location
    -- indentation based on nesting depth
    local depth = location.depth or 0
    local indent_unit = ' '
    local indent = string.rep(indent_unit, depth)

    -- append base indent
    renderer:append(indent, 'Indent')

    -- optionally append the vertical indent icon aligned before the fold icon
    -- don't draw the file-level vertical indent in call-hierarchy flat mode
    local draw_indent_icon = opts.indent_lines.enable and render_indent_line
      and not (self.method == 'incoming_calls' or self.method == 'outgoing_calls')

    if draw_indent_icon then
      renderer:append(' ', 'Indent')
      renderer:append(opts.indent_lines.icon, 'Indent')
      renderer:append(' ', 'Indent')
    else
      renderer:append(' ', 'Indent')
    end

    -- call nodes show a fold icon and can be expanded on demand
    if location.call or location.call_item then
      local fold_key = string.format('%s:%s:%d:%d', self.method, location.uri, location.start_line, location.start_col)
      location.fold_key = fold_key

      local icons = config.options.folds
      local is_folded = folds.is_folded(fold_key)
      local fold_icon = is_folded and icons.fold_closed or icons.fold_open
      -- append fold icon without a leading space so it sits right after the indent icon
      renderer:append(string.format('%s ', fold_icon), 'FoldIcon')
    end

    if location.preview_line then
      local preview_line = location.preview_line.value
      renderer:append(preview_line.before)
      renderer:append(preview_line.inside, 'ListMatch')
      renderer:append(preview_line.after)
    else
      renderer:append(location.full_text)
    end

    renderer:nl()
  end
end

function List:get_cursor()
  return vim.api.nvim_win_get_cursor(self.winnr)
end

function List:get_line()
  return self:get_cursor()[1]
end

function List:get_col()
  return self:get_cursor()[2]
end

function List:get_current_item()
  local line = self:get_line() or 1
  local item = self.items[line]
  return item
end

---@param opts { start: integer, backwards?: boolean, cycle?: boolean }
function List:walk(opts)
  local idx = opts.start
  return function()
    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    idx = idx + (opts.backwards and -1 or 1)
    if opts.cycle then
      idx = ((idx - 1) % line_count) + 1
    end
    local item = self.items[idx]
    if not item or idx > line_count then
      return nil
    end
    return idx, item
  end
end

function List:next(opts)
  opts = opts or {}
  for i, item in
    self:walk({
      start = self:get_line() + (opts.offset or 0),
      cycle = opts.cycle,
    })
  do
    if
      opts.skip_groups
      and item.is_group
      and folds.is_folded(item.filename)
    then
      self:toggle_fold(item)
      return self:next({
        offset = i - self:get_line(), -- offset by how far we've already iterated prior to unfolding
        cycle = opts.cycle,
        skip_groups = true,
      })
    end
    if not (opts.skip_groups and item.is_group) then
      vim.api.nvim_win_set_cursor(self.winnr, { i, self:get_col() })
      return item
    end
  end
  return nil
end

function List:previous(opts)
  opts = opts or {}
  for i, item in
    self:walk({
      start = self:get_line() + (opts.offset or 0),
      cycle = opts.cycle,
      backwards = true,
    })
  do
    if
      opts.skip_groups
      and item.is_group
      and folds.is_folded(item.filename)
    then
      local is_last_line = i == vim.api.nvim_buf_line_count(self.bufnr)
      self:toggle_fold(item)
      return self:previous({
        offset = is_last_line and 0 or item.count, -- offset by how many new items were added after unfolding
        cycle = opts.cycle,
        skip_groups = true,
      })
    end
    if not (opts.skip_groups and item.is_group) then
      vim.api.nvim_win_set_cursor(self.winnr, { i, self:get_col() })
      return item
    end
  end
  return nil
end

function List:get_active_group(opts)
  local current_location = opts.location or self:get_current_item()
  local group = self.groups[current_location.filename]
  if group then
    return group
  end

  -- fallback: try to find the group that contains the location
  for _, g in pairs(self.groups) do
    for _, it in ipairs(g.items) do
      if it == current_location or (it.uri == current_location.uri and it.start_line == current_location.start_line and it.start_col == current_location.start_col) then
        return g
      end
    end
  end

  -- last resort: return a synthetic group with only the current location
  return { items = { current_location } }
end

function List:is_flat()
  return vim.tbl_count(self.groups) == 1
end

function List:toggle_fold(item)
  

  -- support both filename-based groups and nested call nodes
  if item.is_group then
    if folds.is_folded(item.filename) then
      self:open_fold(item)
    else
      self:close_fold(item)
    end
    return
  end

  if item.fold_key then
    if folds.is_folded(item.fold_key) then
      self:open_fold(item)
    else
      self:close_fold(item)
    end
  end
end

function List:open_fold(item)
  -- open filename group
  if item.is_group then
    if not folds.is_folded(item.filename) then
      return
    end
    folds.open(item.filename)
    self:update(self.groups)
    return
  end

  -- open call-node fold
  if item.fold_key then
    if not folds.is_folded(item.fold_key) then
      return
    end

    -- mark open immediately so UI can show the open icon
    folds.open(item.fold_key)

    -- if children already loaded just re-render
    if item._children_loaded then
      self:update(self.groups)
      return
    end

    -- fetch nested calls from LSP for this call_item
    local lsp = require('glance.lsp')
    local bufnr = self.parent_bufnr or vim.api.nvim_get_current_buf()
    -- If we have a cached children subtree, restore it instead of fetching
    if item._children_cache and #item._children_cache > 0 then
      -- find the group that currently contains the item
      local group = nil
      local parent_index = nil
      for _, g in pairs(self.groups) do
        for i, v in ipairs(g.items) do
          if v == item or (v.uri == item.uri and v.start_line == item.start_line and v.start_col == item.start_col) then
            group = g
            parent_index = i
            break
          end
        end
        if group then
          break
        end
      end

      if group and parent_index then
        local new_items = {}
        for i = 1, #group.items do
          table.insert(new_items, group.items[i])
          if i == parent_index then
            for _, c in ipairs(item._children_cache) do
              table.insert(new_items, c)
            end
          end
        end
        group.items = new_items
        item._children_loaded = true
        -- keep cache for future collapses
        self:update(self.groups)
        return
      else
        -- fallback to fetching
      end
    end

    lsp.fetch_calls_for_item(self.method, bufnr, item.call_item, function(results)
      -- build child entries from results and insert after the parent in the group's items
        -- find the group that currently contains the item
        local group = nil
        local parent_index = nil
        for _, g in pairs(self.groups) do
          for i, v in ipairs(g.items) do
            if v == item or (v.uri == item.uri and v.start_line == item.start_line and v.start_col == item.start_col) then
              group = g
              parent_index = i
              break
            end
          end
          if group then
            break
          end
        end

        if not group or not parent_index then
          self:update(self.groups)
          return
        end

      local children = {}
      local depth = (item.depth or 0) + 1
      for _, loc in ipairs(results or {}) do
        local uri = loc.uri or loc.targetUri
        local range = loc.range or loc.targetSelectionRange
        local bufn = vim.uri_to_bufnr(uri)
        local row = range.start.line
        local lines = get_lines(bufn, uri, { row })
        local line = lines and lines[row]
        local start_col = range.start.character
        local end_col = range['end'].character
        local preview_line = nil
        local is_unreachable = false
        if line then
          start_col = utils.get_line_byte_from_position(line, range.start, self.offset_encoding)
          end_col = utils.get_line_byte_from_position(line, range['end'], self.offset_encoding)
          preview_line = get_preview_line({ start_line = row, start_col = start_col, end_col = end_col, end_line = range['end'].line }, 8, line)
        else
          line = ('%s:%d:%d'):format(vim.fn.fnamemodify(vim.uri_to_fname(uri), ':t'), start_col + 1, end_col + 1)
          is_unreachable = true
        end

        table.insert(children, {
          filename = vim.uri_to_fname(uri),
          bufnr = bufn,
          uri = uri,
          preview_line = preview_line,
          is_unreachable = is_unreachable,
          full_text = line or '',
          start_line = range.start.line,
          end_line = range['end'].line,
          start_col = start_col,
          end_col = end_col,
          depth = depth,
          call = loc.call,
          call_item = loc.call_item,
        })
      end

      -- insert children into group's items
      local new_items = {}
      for i = 1, #group.items do
        table.insert(new_items, group.items[i])
        if i == parent_index then
          for _, c in ipairs(children) do
            table.insert(new_items, c)
          end
        end
      end
      group.items = new_items
      item._children_loaded = true

      -- re-render and restore cursor to parent line
      self:update(self.groups)
      for ln, it in pairs(self.items) do
        if it == item or (it.uri == item.uri and it.start_line == item.start_line and it.start_col == item.start_col) then
          vim.api.nvim_win_set_cursor(self.winnr, { ln, self:get_col() })
          break
        end
      end
    end)
  end
end

function List:close_fold(item)
  -- close filename group
  if item.is_group then
    if folds.is_folded(item.filename) then
      return
    end
    local current_line = self:get_line()
    folds.close(item.filename)
    self:update(self.groups)
    return
  end

  -- close call-node fold: remove its children from the group's items
  if item.fold_key then
    if folds.is_folded(item.fold_key) then
      return
    end
    local current_line = self:get_line()
    folds.close(item.fold_key)
    -- find the group that currently contains the item
    local group = nil
    local parent_index = nil
    for _, g in pairs(self.groups) do
      for i, v in ipairs(g.items) do
        if v == item or (v.uri == item.uri and v.start_line == item.start_line and v.start_col == item.start_col) then
          group = g
          parent_index = i
          break
        end
      end
      if group then
        break
      end
    end

    if group and parent_index then
      local parent_depth = item.depth or 0
      -- collect children slice for caching
      local children_slice = {}
      local i = parent_index + 1
      while i <= #group.items and (group.items[i].depth or 0) > parent_depth do
        table.insert(children_slice, group.items[i])
        i = i + 1
      end

      -- cache children on the parent so we can restore nested expansions later
      if #children_slice > 0 then
        item._children_cache = children_slice
      else
        item._children_cache = nil
      end

      -- rebuild group's items without the children slice
      local new_items = {}
      i = 1
      while i <= #group.items do
        if i == parent_index then
          table.insert(new_items, group.items[i])
          i = i + 1
          -- skip the cached children
          while i <= #group.items and (group.items[i].depth or 0) > parent_depth do
            i = i + 1
          end
        else
          table.insert(new_items, group.items[i])
          i = i + 1
        end
      end
      group.items = new_items
      -- mark children as unloaded so reopening will either restore cache or refetch
      item._children_loaded = false
    end

    self:update(self.groups)

    -- restore cursor roughly to parent line
    vim.api.nvim_win_set_cursor(self.winnr, {
      math.max(current_line - (item.index or 0), 1),
      self:get_col(),
    })
  end
end

return List
