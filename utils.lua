local _intstr
if _VERSION == "Lua 5.3" then
  getchar = function (f) return string.unpack("<i1", f:read(1)) end
  getuchar = function (f) return string.unpack("<I1", f:read(1)) end
  getint = function (f) return string.unpack("<i4", f:read(4)) end
  getuint = function (f) return string.unpack("<I4", f:read(4)) end
  _intstr = function (x) return string.pack("<i4", x) end
else
  getchar = function (f)
    local z = string.byte(f:read(1))
    return z >= 0x80 and z - 0x100 or z
  end
  getuchar = function (f)
    return string.byte(f:read(1))
  end
  getint = function (f)
    local z = string.byte(f:read(1))
    z = z + string.byte(f:read(1)) * 0x100
    z = z + string.byte(f:read(1)) * 0x10000
    z = z + string.byte(f:read(1)) * 0x1000000
    return z >= 0x80000000 and z - 0x100000000 or z
  end
  getuint = function (f)
    local z = string.byte(f:read(1))
    z = z + string.byte(f:read(1)) * 0x100
    z = z + string.byte(f:read(1)) * 0x10000
    z = z + string.byte(f:read(1)) * 0x1000000
    return z
  end
  _intstr = function (x)
    x = x % 0x100000000
    return string.char(
      x % 0x100,
      math.floor(x / 0x100) % 0x100,
      math.floor(x / 0x10000) % 0x100,
      math.floor(x / 0x1000000) % 0x100
    )
  end
end
intstr = function (...)
  local t = {}
  for _, v in ipairs(table.pack(...)) do t[#t + 1] = _intstr(v) end
  return table.concat(t)
end
getstr = function (f)
  local str = ""
  while true do
    local c = f:read(1)
    if c == "\0" then break end
    str = str .. c
    end
  return str
end
getstr2 = function (f)
  local str = ""
  repeat
    local line = f:read(256)
    local c = string.gsub(line, "\0.*", "")
    str = str .. c
    f:seek("cur", #c - #line)
  until #c < 256
  return str
end
pad0 = function (s, l)
  return string.sub(s, 1, l) .. string.rep("\x00", l - #s)
end
enum = function (names)
  local t = {}
  for i, k in ipairs(names) do
    t[k] = i
    t[i] = k
  end
  return t
end
size = function (t)
  local z = 0
  for _ in pairs(t) do z = z + 1 end
  return z
end
