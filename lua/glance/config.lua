local utils = require('glance.utils')
local config = {}
config.options = {}

config.namespace = vim.api.nvim_create_namespace('Glance')
config.hl_ns = 'Glance'

---@class GlancePreviewWinOpts
---@field enable boolean
---@field top_char string
---@field bottom_char string

---@class GlanceListOpts
---@field position ('"left"' | '"right"')
---@field width number

---@class GlanceThemeOpts
---@field enable boolean
---@field mode ('"brighten"' | '"darken"' | '"auto"')

---@class GlanceMappingsOpts
---@field list table<string, fun()|false>
---@field preview table<string, fun()|false>

---@class GlanceHooksOpts
---@field before_open fun(results: table[], open: fun(locations: table[]), jump: fun(location: table), method: GlanceMethod)
---@field before_close fun()
---@field after_close fun()

---@class GlanceFoldsOpts
---@field fold_closed string
---@field fold_open string
---@field folded boolean

---@class GlanceIndentLinesOpts
---@field enable boolean
---@field icon string

---@class GlanceWinbarOpts
---@field enable boolean

---@class GlanceOpts
---@field height integer
---@field zindex integer
---@field detached (fun(winid: integer): boolean) | boolean)
---@field preview_win_opts GlancePreviewWinOpts
---@field list GlanceListOpts
---@field theme GlanceThemeOpts
---@field mappings GlanceMappingsOpts
---@field hooks GlanceHooksOpts
---@field folds GlanceFoldsOpts
---@field indent_lines GlanceIndentLinesOpts
---@field winbar GlanceWinbarOpts
---@field preserve_win_context boolean

---@param user_config GlanceOpts | nil
---@param actions GlanceActions
function config.setup(user_config, actions)
  local defaults = {
    height = 18,
    zindex = 45,
    preserve_win_context = true,
    detached = function(winid)
      return vim.api.nvim_win_get_width(winid) < 100
    end,
    preview_win_opts = {
      cursorline = true,
      number = true,
      wrap = true,
    },
    border = {
      enable = false,
      top_char = '―',
      bottom_char = '―',
    },
    list = {
      position = 'right',
      width = 0.33,
    },
    theme = {
      enable = true,
      mode = 'auto',
    },
    mappings = {
      list = {
        ['j'] = actions.next,
        ['k'] = actions.previous,
        ['<Down>'] = actions.next,
        ['<Up>'] = actions.previous,
        ['<Tab>'] = actions.next_location,
        ['<S-Tab>'] = actions.previous_location,
        ['<C-u>'] = actions.preview_scroll_win(5),
        ['<C-d>'] = actions.preview_scroll_win(-5),
        ['v'] = actions.jump_vsplit,
        ['s'] = actions.jump_split,
        ['t'] = actions.jump_tab,
        ['<CR>'] = actions.jump,
        ['l'] = actions.open_fold,
        ['h'] = actions.close_fold,
        ['o'] = actions.jump,
        ['<leader>l'] = actions.enter_win('preview'),
        ['q'] = actions.close,
        ['Q'] = actions.close,
        ['<Esc>'] = actions.close,
        ['<C-q>'] = actions.quickfix,
      },
      preview = {
        ['Q'] = actions.close,
        ['<Tab>'] = actions.next_location,
        ['<S-Tab>'] = actions.previous_location,
        ['<leader>l'] = actions.enter_win('list'),
      },
    },
    hooks = {},
    folds = {
      fold_closed = '',
      fold_open = '',
      folded = true,
    },
    indent_lines = {
      enable = true,
      icon = '│',
    },
    winbar = {
      enable = true,
    },
  }

  config.options = vim.tbl_deep_extend('force', {}, defaults, user_config or {})

  local opts = config.options
  config.options.winbar.enable = opts.winbar.enable
    and vim.fn.has('nvim-0.8') ~= 0

  vim.validate({
    height = { opts.height, 'n', false },
    preserve_win_context = { opts.preserve_win_context, 'b', false },
    list = { opts.list, 't', false },
    position = utils.valid_enum(opts.list.position, { 'left', 'right' }, false),
    width = { opts.list.width, 'n', false },
    theme = { opts.theme, 't', false },
    mode = utils.valid_enum(
      opts.theme.mode,
      { 'darken', 'brighten', 'auto' },
      false
    ),
  })

  if opts.preserve_win_context and vim.fn.has('nvim-0.10.0') == 0 then
    config.options.preserve_win_context = false
  end

  -- Filter disabled mappings
  for _, mappings in pairs(opts.mappings) do
    for key, action in pairs(mappings) do
      if type(key) == 'string' and type(action) == 'boolean' and not action then
        mappings[key] = nil
      end
    end
  end
end

return config
