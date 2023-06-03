local config = require('glance.config')
local Color = require('glance.color')
local M = {}

local links = {
  ListMatch = 'Search',
  PreviewLineNr = 'LineNr',
  ListCursorLine = 'CursorLine',
  PreviewCursorLine = 'CursorLine',
  BorderTop = 'FloatBorder',
  ListBorderBottom = 'FloatBorder',
  PreviewBorderBottom = 'FloatBorder',
  Indent = 'LineNr',
  ListCount = 'Number',
  ListFilename = 'Directory',
  ListFilepath = 'Comment',
}

local winbar_bg_group = 'NormalFloat'

local extract_colors = {
  WinBarFilename = { foreground = 'Normal', background = winbar_bg_group },
  WinBarFilepath = { foreground = 'Comment', background = winbar_bg_group },
  WinBarTitle = { foreground = 'Normal', background = winbar_bg_group },
  PreviewMatch = { foreground = 'Search', background = 'Search' },
}

local function get_hl_value(name, attr)
  local ok, hl = pcall(vim.api.nvim_get_hl_by_name, name, true)

  if not ok then
    return 'NONE'
  end

  hl.foreground = hl.foreground and '#' .. bit.tohex(hl.foreground, 6)
  hl.background = hl.background and '#' .. bit.tohex(hl.background, 6)

  if hl.reverse then
    local normal_bg = get_hl_value('Normal', 'bg')
    hl.background = hl.foreground
    hl.foreground = normal_bg
  end

  if attr then
    attr = ({ bg = 'background', fg = 'foreground' })[attr] or attr
    return hl[attr] or 'NONE'
  end

  return hl.background, hl.foreground
end

local function is_bright_background(color)
  color = color or get_hl_value('Normal', 'bg')
  local luminance = Color.hex2luminance(color)
  return luminance > 0.022
end

local function set_hl(group, value, opts)
  opts = opts or {}
  group = opts.exact and group or config.hl_ns .. group
  local color = vim.tbl_extend('keep', value, { default = true })
  vim.api.nvim_set_hl(0, group, color)
end

local function setup_highlights(mode)
  local bg_normal_value, fg_normal_value = get_hl_value('Normal')
  local bg_normal = Color.new(bg_normal_value)
  local fg_normal = Color.new(fg_normal_value)
  local cursor_line = Color.new(get_hl_value('CursorLine', 'bg'))
  local fg_border_value = get_hl_value('FloatBorder', 'fg')
  local line_nr = Color.new(get_hl_value('LineNr', 'fg'))

  if mode == 'brighten' then
    local preview_bg = bg_normal:brighten(0.28)
    local preview_cursor_line = cursor_line:brighten(0.28)
    local preview_line_nr = line_nr:brighten(0.28)
    local list_bg = bg_normal:brighten(0.43)
    local list_filepath = fg_normal:darken(1.2)
    local list_cursor_line = cursor_line:brighten(0.43)
    local winbar_bg = bg_normal:brighten(0.53)
    local indent = line_nr:brighten(0.15)

    set_hl('PreviewNormal', { bg = preview_bg })
    set_hl('PreviewCursorLine', { bg = preview_cursor_line })
    set_hl('PreviewLineNr', { fg = preview_line_nr })
    set_hl('PreviewSignColumn', { fg = preview_bg })
    set_hl('ListCursorLine', { bg = list_cursor_line })
    set_hl('ListNormal', { bg = list_bg, fg = fg_normal_value })
    set_hl('ListFilepath', { fg = list_filepath })
    set_hl('WinBarFilename', { bg = winbar_bg, fg = fg_normal_value })
    set_hl('WinBarFilepath', { bg = winbar_bg, fg = fg_normal:darken(1.15) })
    set_hl('WinBarTitle', { bg = winbar_bg, fg = fg_normal_value })
    set_hl('Indent', { fg = indent })
    set_hl('FoldIcon', { fg = list_filepath })
    set_hl('ListEndOfBuffer', { bg = list_bg, fg = list_bg })
    set_hl('PreviewEndOfBuffer', { bg = preview_bg, fg = preview_bg })
    set_hl('BorderTop', { bg = winbar_bg, fg = fg_border_value })
    set_hl('ListBorderBottom', { bg = list_bg, fg = fg_border_value })
    set_hl('PreviewBorderBottom', { bg = preview_bg, fg = fg_border_value })
  else
    local preview_bg = bg_normal:darken(0.25)
    local preview_cursor_line = cursor_line:darken(0.25)
    local list_bg = bg_normal:darken(0.4)
    local list_filepath = fg_normal:darken(1.3)
    local list_cursor_line = cursor_line:darken(0.4)
    local winbar_bg = bg_normal:darken(0.5)
    local indent = line_nr:darken(0.3)

    set_hl('PreviewNormal', { bg = preview_bg })
    set_hl('PreviewCursorLine', { bg = preview_cursor_line })
    set_hl('PreviewSignColumn', { fg = preview_bg })
    set_hl('ListCursorLine', { bg = list_cursor_line })
    set_hl('ListNormal', { bg = list_bg, fg = fg_normal_value })
    set_hl('ListFilepath', { fg = list_filepath })
    set_hl('WinBarFilename', { bg = winbar_bg, fg = fg_normal_value })
    set_hl('WinBarFilepath', { bg = winbar_bg, fg = fg_normal:darken(1.2) })
    set_hl('WinBarTitle', { bg = winbar_bg, fg = fg_normal_value })
    set_hl('Indent', { fg = indent })
    set_hl('FoldIcon', { fg = list_filepath })
    set_hl('ListEndOfBuffer', { bg = list_bg, fg = list_bg })
    set_hl('PreviewEndOfBuffer', { bg = preview_bg, fg = preview_bg })
    set_hl('BorderTop', { bg = winbar_bg, fg = fg_border_value })
    set_hl('ListBorderBottom', { bg = list_bg, fg = fg_border_value })
    set_hl('PreviewBorderBottom', { bg = preview_bg, fg = fg_border_value })
  end
end

local function setup_theme()
  local theme_opts = config.options.theme
  local mode = theme_opts.mode

  if mode == 'auto' then
    mode = is_bright_background() and 'darken' or 'brighten'
  end

  if theme_opts.enable then
    pcall(setup_highlights, mode)
  end

  for group, color in pairs(extract_colors) do
    local fg = get_hl_value(color.foreground, 'fg')
    local bg = get_hl_value(color.background, 'bg')
    set_hl(group, { fg = fg, bg = bg })
  end
end

function M.setup()
  set_hl('None', { fg = 'NONE', bg = 'NONE', default = false })
  setup_theme()

  local augroup =
    vim.api.nvim_create_augroup('GlanceColorScheme', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = augroup,
    callback = function()
      setup_theme()
    end,
  })

  for group, link in pairs(links) do
    set_hl(group, { link = link })
  end
end

return M
