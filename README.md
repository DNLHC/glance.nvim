# Glance

A pretty preview window for Neovim that provides VSCode-like peek preview functionality for LSP locations. Glance enables you to preview, navigate, and edit LSP-provided code locations without leaving your current context.

![Glance references screenshot](https://i.imgur.com/ChfG1al.png)

## Features

- Seamless integration with LSP for:
  - Definitions
  - Type definitions
  - References
  - Implementations
- Full editing capabilities within the preview window
- Smart UI highlighting that adapts to your colorscheme
- Intuitive UI
- Minimal configuration required

## Requirements

- Properly configured LSP client
- Neovim >= 0.9.0

## Installation

Using [`lazy.nvim`](https://github.com/folke/lazy.nvim):

```lua
{
    'dnlhc/glance.nvim',
    cmd = 'Glance'
}
```

<details>
<summary><strong>Using mini.deps</strong></summary>
  
```lua
MiniDeps.add({
  source = 'dnlhc/glance.nvim',
})
```

</details>

<details>
<summary><strong>Using packer.nvim</strong></summary>
  
```lua
use({
  'dnlhc/glance.nvim',
  cmd = 'Glance'
})
```

</details>

### Keybindings

```lua
vim.keymap.set('n', 'gD', '<CMD>Glance definitions<CR>')
vim.keymap.set('n', 'gR', '<CMD>Glance references<CR>')
vim.keymap.set('n', 'gY', '<CMD>Glance type_definitions<CR>')
vim.keymap.set('n', 'gM', '<CMD>Glance implementations<CR>')
```

<details>
<summary><strong>Using Vimscript</strong></summary>

```vim
nnoremap gR <CMD>Glance references<CR>
nnoremap gD <CMD>Glance definitions<CR>
nnoremap gY <CMD>Glance type_definitions<CR>
nnoremap gM <CMD>Glance implementations<CR>
```

</details>

## Configuration

<details>
<summary><strong>Default configuration</strong></summary>
The following is the default configuration:

```lua
-- Lua configuration
local glance = require('glance')
local actions = glance.actions

glance.setup({
  height = 18, -- Height of the window
  zindex = 45,

  -- When enabled, adds virtual lines behind the preview window to maintain context in the parent window
  -- Requires Neovim >= 0.10.0
  preserve_win_context = true,

  -- Controls whether the preview window is "embedded" within your parent window or floating
  -- above all windows.
  detached = function(winid)
    -- Automatically detach when parent window width < 100 columns
    return vim.api.nvim_win_get_width(winid) < 100
  end,
  -- Or use a fixed setting: detached = true,

  preview_win_opts = { -- Configure preview window options
    cursorline = true,
    number = true,
    wrap = true,
  },

  border = {
    enable = false, -- Show window borders. Only horizontal borders allowed
    top_char = '―',
    bottom_char = '―',
  },

  list = {
    position = 'right', -- Position of the list window 'left'|'right'
    width = 0.33, -- Width as percentage (0.1 to 0.5)
  },

  theme = {
    enable = true, -- Generate colors based on current colorscheme
    mode = 'auto', -- 'brighten'|'darken'|'auto', 'auto' will set mode based on the brightness of your colorscheme
  },

  mappings = {
    list = {
      ['j'] = actions.next, -- Next item
      ['k'] = actions.previous, -- Previous item
      ['<Down>'] = actions.next,
      ['<Up>'] = actions.previous,
      ['<Tab>'] = actions.next_location, -- Next location (skips groups, cycles)
      ['<S-Tab>'] = actions.previous_location, -- Previous location (skips groups, cycles)
      ['<C-u>'] = actions.preview_scroll_win(5), -- Scroll up the preview window
      ['<C-d>'] = actions.preview_scroll_win(-5), -- Scroll down the preview window
      ['v'] = actions.jump_vsplit, -- Open location in vertical split
      ['s'] = actions.jump_split, -- Open location in horizontal split
      ['t'] = actions.jump_tab, -- Open in new tab
      ['<CR>'] = actions.jump, -- Jump to location
      ['o'] = actions.jump,
      ['l'] = actions.open_fold,
      ['h'] = actions.close_fold,
      ['<leader>l'] = actions.enter_win('preview'), -- Focus preview window
      ['q'] = actions.close, -- Closes Glance window
      ['Q'] = actions.close,
      ['<Esc>'] = actions.close,
      ['<C-q>'] = actions.quickfix, -- Send all locations to quickfix list
      -- ['<Esc>'] = false -- Disable a mapping
    },

    preview = {
      ['Q'] = actions.close,
      ['<Tab>'] = actions.next_location, -- Next location (skips groups, cycles)
      ['<S-Tab>'] = actions.previous_location, -- Previous location (skips groups, cycles)
      ['<leader>l'] = actions.enter_win('list'), -- Focus list window
    },
  },

  hooks = {}, -- Described in Hooks section

  folds = {
    fold_closed = '',
    fold_open = '',
    folded = true, -- Automatically fold list on startup
  },

  indent_lines = {
    enable = true, -- Show indent guidelines
    icon = '│',
  },

  winbar = {
    enable = true, -- Enable winbar for the preview (requires neovim-0.8+)
  },

  use_trouble_qf = false -- Quickfix action will open trouble.nvim instead of built-in quickfix list
})
```

</details>

<details>
<summary><strong>Commands</strong></summary>

- `:Glance references` Show references of the word under the cursor from the LSP server
- `:Glance definitions` Show definitions of the word under the cursor from the LSP server
- `:Glance type_definitions` Show type definitions of the word under the cursor from the LSP server
- `:Glance implementations` Show implementations of the word under the cursor from the LSP server
- `:Glance resume` Resume previously closed session
</details>

<details>
<summary><strong>API</strong></summary>
  
### Actions
Glance provides built-in actions accessed through `require('glance').actions`.
These are used in the mappings.

```lua
local actions = require('glance').actions
```

#### Window Control

```lua
---Opens Glance with specified method, can recieve optional table with hooks
---@param method GlanceMethod
---@param opts? { hooks: GlanceHooks }
actions.open(method, opts)

---Closes the Glance window
actions.close

---Resumes last Glance session
actions.resume

---Enters specified window
---@param win "preview"|"list"
---@return fun() function callback to focus specified window
actions.enter_win(win)
```

#### Navigation

```lua
---Moves cursor to the next item in the list
actions.next

---Moves cursor to the previous item in the list
actions.previous

---Moves to next location (skips groups, cycles)
actions.next_location

---Moves to previous location (skips groups, cycles)
actions.previous_location
```

#### Jump Actions

```lua
 -- Jump to the selected location
 -- Example using a Vim command
 actions.jump({ cmd = 'vsplit' })

 -- Example using a callback function
 actions.jump({
   cmd = function(selected_item)
     vim.cmd('topleft split')
     -- Perform custom actions with the selected item
   end
 })

---Jumps to location in vertical split
actions.jump_vsplit

---Jumps to location in horizontal split
actions.jump_split

---Jumps to location in new tab
actions.jump_tab
```

#### Folding

```lua
---Toggles fold state
actions.toggle_fold

---Opens fold
actions.open_fold

---Closes fold
actions.close_fold
```

#### Other

```lua
---Scrolls preview window
---@param distance integer Number of lines to scroll (negative scrolls up, positive scrolls down)
---@return fun() function callback to scroll the preview window
actions.preview_scroll_win(distance)

---Sends locations to quickfix list
actions.quickfix

-- Check if Glance is currently open
require('glance').is_open()
```

#### Registering custom LSP methods

Glance supports extending its functionality by registering custom LSP methods that are not part of the standard LSP specification. This is particularly useful when working with language servers that provide additional capabilities through non-standard methods.

**Important**: Custom methods must be registered **before** calling the glance `setup`.

```lua
require('glance').register_method({
  method = 'volar/client/findFileReference', -- The LSP method name to be called
  name = 'vue_references',                   -- The command name (used as :Glance vue_references)
  label = 'References',                      -- Display name shown in the Glance UI
})
```

Once registered, you can use the custom method with the command `:Glance vue_references`. The command will trigger the LSP request using the specified custom method.

</details>

<details>
<summary><strong>Hooks</strong></summary>
Hooks allow you to customize Glance's behavior at specific points in its lifecycle. Define them in the setup configuration:

```lua
require('glance').setup({
    hooks = {
        -- your hooks here
    }
})
```

### `before_open`

Called after recieving results from LSP but before opening the preview window. Use this hook to modify the default opening behavior or modify results.

**Note**: This is a blocking hook - Glance won't open until you call the `open` callback.

Parameters:

- `results`: Table of LSP locations
- `open`: Callback to open Glance window
- `jump`: Callback to jump to a location
- `method`: String indicating the call type ('definitions', 'references', etc.)

```lua
hooks = {
  before_open = function(results, open, jump, method)
    open(results)
  end,
}
```

<details>
<summary><strong>More examples</strong></summary>

Skip Glance window and jump directly when there's only one result:

```lua
hooks = {
    before_open = function(results, open, jump, method)
        if #results == 1 then
            jump(results[1])
        else
            open(results)
        end
    end,
}
```

Skip Glance window for single results in current buffer only:

```lua
hooks = {
    before_open = function(results, open, jump, method)
        if #results == 1 then
            local uri = vim.uri_from_bufnr(0)
            local target_uri = results[1].uri or results[1].targetUri

            if target_uri == uri then
                jump(results[1])
            else
                open(results)
            end
        else
            open(results)
        end
    end,
}
```

</details>

### `before_close`

Called right before the Glance window closes.

### `after_close`

Called after the Glance window closes.

</details>

<details>
<summary><strong>Highlight groups</strong></summary>

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

</details>

## Alternatives

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [glepnir/lspsaga.nvim](https://github.com/glepnir/lspsaga.nvim)
- [folke/trouble.nvim](https://github.com/folke/trouble.nvim)
- [rmagatti/goto-preview](https://github.com/rmagatti/goto-preview)
