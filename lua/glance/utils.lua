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

function utils.is_float_win(winnr)
  if winnr == nil or not vim.api.nvim_win_is_valid(winnr) then
    return
  end
  return vim.api.nvim_win_get_config(winnr).zindex ~= nil
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

function utils.get_line_byte_from_position(line, position, offset_encoding)
  -- LSP's line and characters are 0-indexed
  -- Vim's line and columns are 1-indexed
  local col = position.character
  -- When on the first character, we can ignore the difference between byte and
  -- character
  if col > 0 then
    local ok, result
    ok, result = pcall(vim.str_byteindex, line, offset_encoding, col)
    if ok then
      return result
    end
    ok, result =
      pcall(vim.str_byteindex, line, col, offset_encoding == 'utf-16')
    if ok then
      return result
    end
    ok, result =
      pcall(vim.lsp.util._str_byteindex_enc, line, col, offset_encoding)
    if ok then
      return result
    end
    return math.min(#line, col)
  end
  return col
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
  log(msg, vim.log.levels.INFO)
end

function utils.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer = nil
    end

    timer = vim.defer_fn(function()
      fn(unpack(args))
      timer = nil
    end, delay)
  end
end

--- Throttles a function on the leading edge. Automatically `schedule_wrap()`s.
---
--@param fn (function) Function to throttle
--@param timeout (number) Timeout in ms
--@returns (function, timer) throttled function and timer. Remember to call
---`timer:close()` at the end or you will leak memory!
function utils.throttle_leading(fn, ms)
  local timer = vim.loop.new_timer()
  local running = false

  local function wrapped_fn(...)
    if not running then
      timer:start(ms, 0, function()
        running = false
      end)
      running = true
      pcall(vim.schedule_wrap(fn), select(1, ...))
    end
  end

  return wrapped_fn, timer
end

return utils
