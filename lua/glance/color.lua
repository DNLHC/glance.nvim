local utils = require('glance.utils')
Color = {}
Color.__index = Color

-- Most of the code taken from chroma-js library
-- https://github.com/gka/chroma.js/

function Color.hex2rgb(hex)
  hex = hex:gsub('#', '')
  return tonumber(hex:sub(1, 2), 16),
    tonumber(hex:sub(3, 4), 16),
    tonumber(hex:sub(5, 6), 16)
end

function Color.rgb2hex(r, g, b)
  r = math.min(math.max(0, utils.round(r)), 255)
  g = math.min(math.max(0, utils.round(g)), 255)
  b = math.min(math.max(0, utils.round(b)), 255)
  return '#' .. ('%02X%02X%02X'):format(r, g, b)
end

local function luminance_x(x)
  x = x / 255
  return x <= 0.03928 and x / 12.92 or math.pow((x + 0.055) / 1.055, 2.4)
end

function Color.rgb2luminance(r, g, b)
  r = luminance_x(r)
  g = luminance_x(g)
  b = luminance_x(b)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

function Color.hex2luminance(hex)
  if not hex or hex == 'NONE' then
    return 0
  end
  return Color.rgb2luminance(Color.hex2rgb(hex))
end

local LAB = {
  Kn = 18,

  Xn = 0.950470,
  Yn = 1,
  Zn = 1.088830,

  t0 = 0.137931034,
  t1 = 0.206896552,
  t2 = 0.12841855,
  t3 = 0.008856452,
}

local function is_nan(v)
  return type(v) == 'number' and v ~= v
end

local function xyz_rgb(r)
  return 255
    * (r <= 0.00304 and 12.92 * r or 1.055 * math.pow(r, 1 / 2.4) - 0.055)
end

local function lab_xyz(t)
  return t > LAB.t1 and t * t * t or LAB.t2 * (t - LAB.t0)
end

local function lab2rgb(l, a, b)
  local x, y, z, r, g, b_

  y = (l + 16) / 116
  x = is_nan(a) and y or y + a / 500
  z = is_nan(b) and y or y - b / 200

  y = LAB.Yn * lab_xyz(y)
  x = LAB.Xn * lab_xyz(x)
  z = LAB.Zn * lab_xyz(z)

  r = xyz_rgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z)
  g = xyz_rgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
  b_ = xyz_rgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)

  return r, g, b_
end

local function rgb_xyz(r)
  r = r / 255
  if r <= 0.04045 then
    return r / 12.92
  end
  return math.pow((r + 0.055) / 1.055, 2.4)
end

local function xyz_lab(t)
  if t > LAB.t3 then
    return math.pow(t, 1 / 3)
  end

  return t / LAB.t2 + LAB.t0
end

local function rgb2xyz(r, g, b)
  r = rgb_xyz(r)
  g = rgb_xyz(g)
  b = rgb_xyz(b)

  local x = xyz_lab((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / LAB.Xn)
  local y = xyz_lab((0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / LAB.Yn)
  local z = xyz_lab((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / LAB.Zn)

  return x, y, z
end

local function rgb2lab(r, g, b)
  local x, y, z = rgb2xyz(r, g, b)
  local l = 116 * y - 16
  l = l < 0 and 0 or l
  local a = 500 * (x - y)
  b = 200 * (y - z)
  return l, a, b
end

function Color:modify(amount)
  return amount > 0 and self:brighten(amount) or self:darken(math.abs(amount))
end

function Color:darken(amount)
  local lab = self.lab
  local l = lab[1] - (LAB.Kn * amount)
  local r, g, b = lab2rgb(l, lab[2], lab[3])
  return Color.rgb2hex(r, g, b)
end

function Color:brighten(amount)
  return self:darken(-amount)
end

function Color.new(hex)
  if not hex or hex == 'NONE' then
    return nil
  end
  local self = { Color.hex2rgb(hex) }
  self.lab = { rgb2lab(unpack(self)) }
  self.hex = hex

  return setmetatable(self, Color)
end

return Color
