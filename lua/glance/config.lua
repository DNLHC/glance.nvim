local utils = require('glance.utils')
local config = {}
config.options = {}

config.namespace = vim.api.nvim_create_namespace('Glance')
config.hl_ns = 'Glance'

function config.setup(user_config, actions)
  local defaults = {
    height = 18,
    border = {
      enable = false,
      top_char = '-',
      bottom_char = '-',
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
        ['o'] = actions.jump,
        ['<leader>l'] = actions.enter_win('preview'),
        ['q'] = actions.close,
        ['Q'] = actions.close,
        ['<Esc>'] = actions.close,
      },
      preview = {
        ['Q'] = actions.close,
        ['<Tab>'] = actions.next_location,
        ['<S-Tab>'] = actions.previous_location,
        ['<leader>l'] = actions.enter_win('list'),
      },
    },
    folds = {
      fold_closed = '',
      fold_open = '',
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
end

return config
