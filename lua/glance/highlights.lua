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

  if hl.reverse then
    hl.background = hl.foreground and '#' .. bit.tohex(hl.foreground, 6)
    hl.foreground = get_hl_value('Normal', 'bg')
  else
    hl.foreground = hl.foreground and '#' .. bit.tohex(hl.foreground, 6)
    hl.background = hl.background and '#' .. bit.tohex(hl.background, 6)
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

local function create_color(color, amount)
  if not color or color == 'NONE' then
    return 'NONE'
  end
  return Color.new(color):modify(amount)
end

local function setup_highlights(mode)
  local normal_bg, normal_fg = get_hl_value('Normal')
  local cursor_line_bg = get_hl_value('CursorLine', 'bg')
  local border_fg = get_hl_value('FloatBorder', 'fg')
  local line_nr_fg = get_hl_value('LineNr', 'fg')

  local factor = mode == 'brighten' and 1 or -1

  local colors = {
    preview = {
      bg = create_color(normal_bg, 0.28 * factor),
      cursor = create_color(cursor_line_bg, 0.28 * factor),
      line_nr = create_color(line_nr_fg, 0.28 * factor),
    },
    list = {
      bg = create_color(normal_bg, 0.43 * factor),
      cursor = create_color(cursor_line_bg, 0.43 * factor),
      filepath = create_color(normal_fg, -1.2),
    },
    winbar = {
      bg = create_color(normal_bg, 0.53 * factor),
      filepath = create_color(normal_fg, -1.2),
    },
    indent = create_color(line_nr_fg, 0.2 * factor),
  }

  local highlights = {
    PreviewNormal = { bg = colors.preview.bg },
    PreviewCursorLine = { bg = colors.preview.cursor },
    PreviewLineNr = { fg = colors.preview.line_nr },
    PreviewSignColumn = { fg = colors.preview.bg },
    ListCursorLine = { bg = colors.list.cursor },
    ListNormal = { bg = colors.list.bg, fg = normal_fg },
    ListFilepath = { fg = colors.list.filepath },
    WinBarFilename = { bg = colors.winbar.bg, fg = normal_fg },
    WinBarFilepath = { bg = colors.winbar.bg, fg = colors.winbar.filepath },
    WinBarTitle = { bg = colors.winbar.bg, fg = normal_fg },
    Indent = { fg = colors.indent },
    FoldIcon = { fg = colors.list.filepath },
    ListEndOfBuffer = { bg = colors.list.bg, fg = colors.list.bg },
    PreviewEndOfBuffer = { bg = colors.preview.bg, fg = colors.preview.bg },
    BorderTop = { bg = colors.winbar.bg, fg = border_fg },
    ListBorderBottom = { bg = colors.list.bg, fg = border_fg },
    PreviewBorderBottom = { bg = colors.preview.bg, fg = border_fg },
  }

  -- Apply highlights
  for group, opts in pairs(highlights) do
    set_hl(group, opts)
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
