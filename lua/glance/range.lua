local Range = {}
Range.__index = Range

function Range:new(start_line, start_col, end_line, end_col)
  local scope = {}
  if
    start_line > end_line or (start_line == end_line and start_col > end_col)
  then
    scope.start_line = end_line
    scope.start_col = end_col
    scope.end_line = start_line
    scope.end_col = start_col
  else
    scope.start_line = start_line
    scope.start_col = start_col
    scope.end_line = end_line
    scope.end_col = end_col
  end

  setmetatable(scope, self)
  return scope
end

function Range._contains_position(range, pos)
  if pos.line < range.start_line or pos.line > range.end_line then
    return false
  end

  if pos.line == range.start_line and pos.col < range.start_col then
    return false
  end

  if pos.line == range.end_line and pos.col > range.end_col then
    return false
  end
  return true
end

function Range:contains_position(pos)
  return Range._contains_position(self, pos)
end

function Range._strict_contains_position(range, pos)
  if pos.line < range.start_line or pos.line > range.end_line then
    return false
  end

  if pos.line == range.start_line and pos.col <= range.start_col then
    return false
  end

  if pos.line == range.end_line and pos.col >= range.end_col then
    return false
  end
  return true
end

function Range:strict_contains_position(pos)
  return Range._strict_contains_position(self, pos)
end

return Range
