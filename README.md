# Glance

A pretty window for previewing, navigating and editing your LSP locations in one place, inspired by vscode's peek preview.

![Glance references screenshot](https://i.imgur.com/86K5ljv.png)

## Requirements

- Properly configured LSP client
- Neovim >= 0.7.0

## Install

Install the plugin with your preferred plugin manager.

### Vim Plug

```vim
Plug 'dnlhc/glance.nvim'
```

### Packer

```lua
use({
  "dnlhc/glance.nvim",
  config = function()
    require('glance').setup({
      -- your configuration
    })
  end,
})
```

## Configuration

The following is the default configuration:

```lua
-- Lua configuration
local glance = require('glance')
local actions = glance.actions

glance.setup({
  height = 18, -- Height of the window
  border = {
    enable = false, -- Show window borders. Only horizontal borders allowed
    top_char = '-',
    bottom_char = '-',
  },
  list = {
    position = 'right', -- Position of the list window 'left'|'right'
    width = 0.33, -- 33% width relative to the active window, min 0.1, max 0.5
  },
  theme = { -- This feature might not work properly in nvim-0.7.2
    enable = true, -- Will generate colors for the plugin based on your current colorscheme
    mode = 'auto', -- 'brighten'|'darken'|'auto', 'auto' will set mode based on the brightness of your colorscheme
  },
  mappings = {
    list = {
      ['j'] = actions.next, -- Bring the cursor to the next item in the list
      ['k'] = actions.previous, -- Bring the cursor to the previous item in the list
      ['<Down>'] = actions.next,
      ['<Up>'] = actions.previous,
      ['<Tab>'] = actions.next_location, -- Bring the cursor to the next location skipping groups in the list
      ['<S-Tab>'] = actions.previous_location, -- Bring the cursor to the previous location skipping groups in the list
      ['<C-u>'] = actions.preview_scroll_win(5),
      ['<C-d>'] = actions.preview_scroll_win(-5),
      ['v'] = actions.jump_vsplit,
      ['s'] = actions.jump_split,
      ['t'] = actions.jump_tab,
      ['<CR>'] = actions.jump,
      ['o'] = actions.jump,
      ['<leader>l'] = actions.enter_win('preview'), -- Focus preview window
      ['q'] = actions.close,
      ['Q'] = actions.close,
      ['<Esc>'] = actions.close,
    },
    preview = {
      ['Q'] = actions.close,
      ['<Tab>'] = actions.next_location,
      ['<S-Tab>'] = actions.previous_location,
      ['<leader>l'] = actions.enter_win('list'), -- Focus list window
    },
  },
  folds = {
    fold_closed = '',
    fold_open = '',
    folded = true, -- Automatically fold list on startup
  },
  indent_lines = {
    enable = true,
    icon = '│',
  },
  winbar = {
    enable = true, -- Available strating from nvim-0.8+
  },
})
```

## Usage

### Commands

- `:Glance references` show references of the word under the cursor from the LSP server
- `:Glance definitions` show definitions of the word under the cursor from the LSP server
- `:Glance type_definitions` show type definitions of the word under the cursor from the LSP server
- `:Glance implementations` show implementations of the word under the cursor from the LSP server

### Example keybindings

```vim
" VimScript
nnoremap gR <CMD>Glance references<CR>
nnoremap gD <CMD>Glance definitions<CR>
nnoremap gY <CMD>Glance type_definitions<CR>
nnoremap gM <CMD>Glance implementations<CR>
```

```lua
-- Lua
vim.keymap.set('n', 'gD', '<CMD>Glance definitions<CR>')
vim.keymap.set('n', 'gR', '<CMD>Glance references<CR>')
vim.keymap.set('n', 'gY', '<CMD>Glance type_definitions<CR>')
vim.keymap.set('n', 'gM', '<CMD>Glance implementations<CR>')
```

## Highlights

The following list shows all the highlight groups defined for glance.nvim

- `GlancePreviewNormal`
- `GlancePreviewMatch`
- `GlancePreviewCursorLine`
- `GlancePreviewSignColumn`
- `GlancePreviewEndOfBuffer`
- `GlancePreviewLineNr`
- `GlancePreviewBorderBottom`
- `GlanceWinBarFilename`
- `GlanceWinBarFilepath`
- `GlanceWinBarTitle`
- `GlanceListNormal`
- `GlanceListFilename`
- `GlanceListFilepath`
- `GlanceListCount`
- `GlanceListMatch`
- `GlanceListCursorLine`
- `GlanceListEndOfBuffer`
- `GlanceListBorderBottom`
- `GlanceFoldIcon`
- `GlanceIndent`
- `GlanceBorderTop`

## Alternatives

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [glepnir/lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim)
- [folke/trouble.nvim](https://github.com/folke/trouble.nvim)
- [rmagatti/goto-preview](https://github.com/rmagatti/goto-preview)
