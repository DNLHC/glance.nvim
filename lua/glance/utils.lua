local utils = {}

function utils.create_push_tagstack(parent_winnr)
  local pos = vim.api.nvim_win_get_cursor(0)
  local current_word = vim.fn.expand('<cword>')
  local from = { vim.api.nvim_get_current_buf(), pos[1], pos[2], 0 }
  local items = { { tagname = current_word, from = from } }

  return function()
    vim.api.nvim_win_call(parent_winnr, function()
      vim.cmd("norm! m'")
      vim.fn.settagstack(parent_winnr, { items = items }, 't')
    end)
  end
end

function utils.list_to_tree(list)
  local tree = {}
  for _, item in ipairs(list) do
    if not tree[item.filename] then
      tree[item.filename] =
        { filename = item.filename, uri = item.uri, items = {} }
    end

    if not vim.tbl_isempty(item) then
      table.insert(tree[item.filename].items, item)
    end
  end

  return tree
end

function utils.valid_enum(arg, values, optional)
  return {
    arg,
    function(v)
      return (optional and v == nil) or vim.tbl_contains(values, v)
    end,
    table.concat(
      vim.tbl_map(function(v)
        return ([['%s']]):format(v)
      end, values),
      '|'
    ),
  }
end
function utils.get_word_until_position(pos, text)
  pos = math.max(0, pos)
  local str = string.sub(text, 0, pos)

  if string.len(str) == 0 then
    return {
      match = '',
      start_col = 0,
      end_col = pos,
    }
  end

  local match = nil
  local re = vim.regex([[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]])
  local index = 0

  while true do
    local start_col, end_col = re:match_str(str)

    if start_col == nil then
      break
    end

    local curr_match = string.sub(str, start_col + 1, end_col)

    if not curr_match and match then
      break
    end

    match = curr_match
    index = index + end_col
    str = string.sub(str, end_col + 1)
  end

  if match then
    return {
      match = match,
      start_col = index - string.len(match),
      end_col = index,
    }
  end

  return {
    match = '',
    start_col = pos,
    end_col = pos,
  }
end

function utils.tbl_find(T, predicate)
  for index, value in ipairs(T) do
    if predicate(value, index) then
      return value, index
    end
  end
  return nil
end

function utils.get_value_in_range(start_col, end_col, text)
  if start_col == end_col then
    return ''
  end
  return string.sub(text, start_col + 1, end_col)
end

function utils.win_set_options(winnr, opts)
  for opt, value in pairs(opts) do
    vim.api.nvim_win_set_option(winnr, opt, value)
  end
end

function utils.buf_set_options(bufnr, opts)
  for opt, value in pairs(opts) do
    vim.api.nvim_buf_set_option(bufnr, opt, value)
  end
end

function utils.round(n)
  return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end

function utils.capitalize(str)
  return (str:gsub('^%l', string.upper))
end

local function log(msg, level)
  vim.notify(msg, level, { title = 'Glance' })
end

function utils.warn(msg)
  log(msg, vim.log.levels.WARN)
end

function utils.error(msg)
  log(msg, vim.log.levels.ERROR)
end

function utils.info(msg)
  log(msg, vim.log.levels.ERROR)
end

return utils
