require "luaFTM"

local FXCHAR = {}
string.gsub("FBDCE3?HI047PGZ12VYQRASXMHIJW", "()(.)", function (x, y) FXCHAR[x] = y end)
FXCHAR[0] = " "

local rowView = {}
rowView.__metatable = "rowView"
rowView.__index = rowView

function rowView:new (ftm, track, frame, row)
  local t = {ftm = ftm, track = track or 1, frame = frame or 1, row = row or 1, span = ftm:getChCount()}
  setmetatable(t, self)
  t.lastFX = t:globalFX()
  return t
end

function rowView:__tostring ()
  return string.format("T%02XF%02XR%02X", self.track, self.frame - 1, self.row - 1)
end

function rowView:get (ch)
  if ch < 1 or ch > self.span then error("attempt to access a non-existent channel with rowView", 2) end
  local tr = self.ftm.track[self.track]
  local blank = not tr.pattern[ch] or
                not tr.pattern[ch][tr.frame[self.frame][ch]] or
                not tr.pattern[ch][tr.frame[self.frame][ch]][self.row]
  return blank and {note = 0, oct = 0, inst = 0x40, vol = 0x10, fx = {}} or tr.pattern[ch][tr.frame[self.frame][ch]][self.row]
end

function rowView:set (ch, t)
  if ch < 1 or ch > self.span then error("attempt to access a non-existent channel with rowView", 2) end
  local tr = self.ftm.track[self.track]
  tr.pattern[ch][tr.frame[self.frame][ch]][self.row] = t
  self.lastFX = self:globalFX()
end

function rowView:globalFX ()
  local skip, speed, tempo
  for i = 1, self.span do
    local n = self:get(i)
    for j = 1, 4 do
      if n.fx[j] then
        local fx = n.fx[j].name
        if n.fx[j].name == FX.JUMP or n.fx[j].name == FX.SKIP or n.fx[j].name == FX.HALT then
          skip = n.fx[j]
        elseif n.fx[j].name == FX.GROOVE then
          speed = n.fx[j]
        elseif n.fx[j].name == FX.SPEED then
          if n.fx[j].param >= self.ftm.param.FxxSplit then
            tempo = n.fx[j]
          else
            speed = n.fx[j]
          end
        end
      end
    end
  end
  
  local fx = {}
  table.insert(fx, skip)
  table.insert(fx, speed)
  table.insert(fx, tempo)
  return fx
end

function rowView:step (play)
  -- nil:   jump upon skip effects
  -- false: do not jump upon skip effects
  -- true:  jump upon skip effects, resolve effect parameter
  local f, r = self.frame, self.row + 1
  local tr = self.ftm.track[self.track]
  f, r = f + math.floor((r - 1) / tr.rows), (r - 1) % tr.rows + 1
  
  if play ~= false then
    local g = self:globalFX()
    for _, v in pairs(self:globalFX()) do
      if v.name == FX.JUMP then
        f, r = (play and v.param or self.frame) + 1, 1
      elseif v.name == FX.SKIP then
        f, r = self.frame + 1, play and v.param + 1 or 1
      elseif v.name == FX.HALT then
        f, r = self.frame + 1, 1
      end
    end
  end
  
  self.frame, self.row = (f - 1) % #tr.frame + 1, r
  self.lastFX = self:globalFX()
end

function rowView:stepBack ()
  self.lastFX = self:globalFX()
end

function rowView:display (f, e)
  local noteStr = function (n, ch)
    if n.note == 0 then return "..." end
    if n.note == 0x0D then return "===" end
    if n.note == 0x0E then return "---" end
    if n.note == 0x0F then return " ^" .. n.oct end
    if ch == 0x04 then -- noise
      return string.format("%01X-#", (n.note + n.oct * 12 - 1) % 0x10)
    end
    return string.sub("CCDDEFFGGAAB", n.note, n.note) .. string.sub("-#-#--#-#-#-", n.note, n.note) .. n.oct
  end
  local instStr = function (n) return n.inst == 0x40 and ".." or string.format("%02X", n.inst) end
  local volStr = function (n) return n.vol == 0x10 and "." or string.format("%01X", n.vol) end
  local effStr = function (n, ch)
    local t = {}
    for i = 1, self.ftm.track[self.track].maxeffect[ch] do
      t[i] = n.fx[i] and FXCHAR[n.fx[i].name] .. string.format("%02X", n.fx[i].param) or "..."
    end
    return table.concat(t, " ")
  end
  
  local r = {}
  for i = f or 1, e or self.span do
    local n = self:get(i)
    table.insert(r, string.format("%s %s %s %s", noteStr(n, i), instStr(n), volStr(n), effStr(n, i)))
  end
  return table.concat(r, "  ")
end

return rowView