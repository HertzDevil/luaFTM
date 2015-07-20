-- luaFTM - lightweight FamiTracker module library
-- Copyright (C) 2015 HertzDevil
-- MIT License.

require "luaFTM.utils"

CHIP = {APU = 0, VRC6 = 1, VRC7 = 2, FDS = 4, MMC5 = 8, N163 = 16, S5B = 32}
INST = enum {"APU", "VRC6", "VRC7", "FDS", "N163", "S5B"}
CHANS = {[CHIP.APU] = 5, [CHIP.VRC6] = 3, [CHIP.VRC7] = 6, [CHIP.FDS] = 1, [CHIP.MMC5] = 2, [CHIP.S5B] = 3}
FX = enum {
	"SPEED",
	"JUMP",
	"SKIP",
	"HALT",
	"VOLUME",
	"PORTAMENTO",
	"PORTAOFF",
	"SWEEPUP",
	"SWEEPDOWN",
	"ARPEGGIO",
	"VIBRATO",
	"TREMOLO",
	"PITCH",
	"DELAY",
	"DAC",
	"PORTA_UP",
	"PORTA_DOWN",
	"DUTY_CYCLE",
	"SAMPLE_OFFSET",
	"SLIDE_UP",
	"SLIDE_DOWN",
	"VOLUME_SLIDE",
	"NOTE_CUT",
	"RETRIGGER",
	"DELAYED_VOLUME",
	"FDS_MOD_DEPTH",
	"FDS_MOD_SPEED_HI",
	"FDS_MOD_SPEED_LO",
	"DPCM_PITCH",
	"SUNSOFT_ENV_LO",
	"SUNSOFT_ENV_HI",
	"SUNSOFT_ENV_TYPE",
	"NOTE_RELEASE",
	"GROOVE",
	"TRANSPOSE",
	"N163_WAVE_BUFFER",
	"FDS_VOLUME",
}
FX.NONE = 0; FX[0] = "NONE"

local FTM = {}
FTM.__metatable = "FamiTracker Module"
FTM.__index = FTM

function FTM:hasChip (ch)
  return ch == CHIP.APU or math.floor(self.param.chip / ch) % 2 ~= 0
end

function FTM:getChCount ()
  local x = self.param.namcoCh
  for i, v in pairs(CHANS) do
    if self:hasChip(i) then x = x + v end
  end
  return x
end

function FTM:getTrackChs ()
  local t = {}
  for i = 1, 7 do
    local ch = math.floor(2 ^ (i - 2))
    if self:hasChip(ch) then
      for j = 1, ch == CHIP.N163 and self.param.namcoCh or CHANS[ch] do
        table.insert(t, {ch, j})
      end
    end
  end
  return t
end

function FTM:newTrack ()
  local t = {speed = 6, tempo = 150, rows = 64}
  t.maxeffect = {}
  t.frame = {{}}
  t.pattern = {}
  for i = 1, self:getChCount() do
    t.maxeffect[i] = 1
    t.frame[1][i] = 1
    t.pattern[i] = {}
  end
  return t
end

function FTM:newFTM ()
  local ftm = {version = 0x440, track = {}, inst = {}, seqAPU = {{}, {}, {}, {}, {}}, dpcm = {}}
  setmetatable(ftm, self)
  ftm.param = {chip = 0, machine = "NTSC", rate = 0, newVibrato = true, highlight = {4, 16}, FxxSplit = 32, namcoCh = 0}
  ftm.info = {title = "", author = "", copyright = ""}
  ftm.comment = {open = false, str = ""}
  ftm.track[1] = ftm:newTrack()
  return ftm
end

function FTM:loadFTI (name)
end

function FTM:saveFTI (name)
end

function FTM:loadFTM (name)
  local ftm = FTM:newFTM()
  local f = assert(io.open(name, "rb"))
  local error = function (str, e) f:close(); error(str, (e or 1) + 1) end
  if f:read(18) ~= "FamiTracker Module" then error("File " .. name .. " is not a valid FamiTracker module") end
  ftm.ver = getint(f)
  if ftm.version > 0x440 then error("File " .. name .. " is not supported in this version") end
  local currentPos, blockSize
  
  local blockTable = {}
  blockTable.PARAMS = function (t, ver)
    if ver == 1 then
      t.track[1].speed = getint(f)
    else
      t.param.chip = getchar(f)
    end
    t.param.chcount = getint(f)
    t.param.machine = getint(f) == 1 and "PAL" or "NTSC"
    t.param.rate = getint(f)
    if t.param.rate == 0 then t.param.rate = t.param.machine == "PAL" and 50 or 60 end
    t.param.newVibrato = ver > 2 and (getint(f) > 0) or false
    if ver > 3 then
      t.param.highlight[1] = getint(f)
      t.param.highlight[2] = getint(f)
    end
    if t.version == 0x200 then
      if t.track[1].speed < 20 then t.track[1].speed = t.track[1].speed + 1 end
    end
    if ver == 1 then
      if t.track[1].speed > 19 then
        t.track[1].tempo, t.track[1].speed = t.track[1].speed, 6
      else
        t.track[1].tempo = t.param.machine == "PAL" and 125 or 150
      end
    end
    t.param.namcoCh = ver >= 5 and t:hasChip(CHIP.N163) and getint(f) or 0
    t.param.FxxSplit = ver >= 6 and getint(f) or 21
    if t.param.chcount ~= t:getChCount() then
      error("Channel count mismatch (got " .. t.param.chcount .. ", expected " .. t:getChCount() .. ")")
    end
    ftm.track[1] = ftm:newTrack()
    if ftm:hasChip(CHIP.VRC6) then ftm.seqVRC6 = {{}, {}, {}, {}, {}} end
    if ftm:hasChip(CHIP.FDS) then ftm.seqFDS = {{}, {}, {}} end
    if ftm:hasChip(CHIP.N163) then ftm.seqN163 = {{}, {}, {}, {}, {}} end
    if ftm:hasChip(CHIP.S5B) then ftm.seqS5B = {{}, {}, {}, {}, {}} end
  end
  
  blockTable.INFO = function (t, ver)
    t.info.title = string.gsub(f:read(32), "\0.*", "")
    t.info.author = string.gsub(f:read(32), "\0.*", "")
    t.info.copyright = string.gsub(f:read(32), "\0.*", "")
  end
  
  blockTable.HEADER = function (t, ver)
    if ver == 1 then
      error("BLOCK VERSION IS NOT IMPLEMENTED")
      return
    end
    for i = 1, 1 + getchar(f) do
      if not t.track[i] then t.track[i] = t:newTrack() end
    end
    if ver >= 3 then
      for i = 1, #t.track do t.track[i].title = getstr(f) end
    end
    for i = 1, t.param.chcount do
      getuchar(f) -- channel type
      for j = 1, #t.track do
        t.track[j].maxeffect[i] = getuchar(f) + 1
      end
    end
    if ver >= 4 then
      -- highlight
    end
  end
  
  blockTable.INSTRUMENTS = function (t, ver)
    local instSeq = function (v)
      local count = getint(f)
      for i = 1, count do
        local enable = getchar(f)
        local index = getuchar(f) + 1
        if enable ~= 0 then v.seq[i] = index end
      end
    end
    local inst2A03 = function (v)
      instSeq(v)
      v.dpcm = {}
      for i = 1, 12 * (ver == 1 and 6 or 8) do
        local id = getuchar(f)
        local pitch = getuchar(f)
        local delta = getchar(f)
        if id ~= 0 then
          v.dpcm[i] = {id = id, pitch = pitch}
          if delta ~= -1 then v.dpcm[i].delta = delta end
        end
      end
    end
    local instVRC7 = function (v)
      v.seq = nil
      v.patch = getint(f)
      v.custom = {}
      for i = 1, 8 do v.custom[i] = getuchar(f) end
    end
    local instFDS = function (v)
      v.wave = {}
      v.mod = {}
      for i = 1, 64 do v.wave[i] = getuchar(f) end
      for i = 1, 32 do v.mod[i] = getuchar(f) end
      v.FMrate = getint(f)
      v.FMdepth = getint(f)
      v.FMdelay = getint(f)
      local a = getuint(f)
      local b = getuint(f)
      f:seek("cur", -8)
      if a >= 256 or b % 0x100 ~= 0 then for i = 1, ver > 2 and 3 or 2 do
        local count = getuchar(f)
        v.seq[i] = {}
        local s = v.seq[i]
        local loop = getint(f)
        if loop >= 0 and loop < count then s.loop = loop + 1 end
        local rel = getint(f)
        if rel >= 0 and rel < count then s.release = rel + 1 end
        s.setting = getuint(f)
        for j = 1, count do s[#s + 1] = getchar(f) end
        table.insert(ftm.seqFDS[i], s)
      end end
      if ver <= 3 then for i = 1, #v.seq[1] do v.seq[1][i] = v.seq[1][i] * 2 end end
    end
    local instN163 = function (v)
      instSeq(v)
      v.wave = {}
      local size = getuint(f)
      v.wavePos = getuint(f)
      local count = getuint(f)
      for i = 1, count do
        v.wave[i] = {}
        for j = 1, size do v.wave[i][j] = getuchar(f) end
      end
    end
    
    local func = {inst2A03, instSeq, instVRC7, instFDS, instN163, instSeq}
    for i = 1, getint(f) do
      local ins = {seq = {}}
      ftm.inst[getint(f) + 1] = ins
      ins.instType = getuchar(f)
      assert(func[ins.instType], "Unknown instrument type")
      func[ins.instType](ins)
      local size = getuint(f)
      ins.name = f:read(size)
    end
  end
  
  local readSeqNew = function (chipName)
    local seqt = "seq" .. chipName
    return function (t, ver)
      local count = getuint(f)
      local idMemo, typeMemo = {}, {}
      for i = 1, count do
        local id = getuint(f) + 1
        local seqType = getuint(f) + 1
        table.insert(idMemo, id)
        table.insert(typeMemo, seqType)
        local length = getuchar(f)
        local loop = getint(f)
        if loop == length then loop = -1 end
        local s = {id = id}
        ftm[seqt][seqType][id] = s
        if loop >= 0 and loop < count then s.loop = loop + 1 end
        if ver == 4 then
          local rel = getint(f)
          if rel >= 0 and rel < count then s.release = rel + 1 end
          s.setting = getuint(f)
        end
        for j = 1, length do s[#s + 1] = getchar(f) end
      end
      if ver == 5 then
        for id = 1, 128 do for i = 1, 5 do
          local s = ftm[seqt][i][id]
          local rel = getuint(f)
          local setting = getuint(f)
          if s then
            if rel >= 0 and rel < #s then s.release = rel + 1 end
            s.setting = setting
          end
        end end
      elseif ver >= 6 then
        for i = 1, count do
          local s = ftm[seqt][typeMemo[i]][idMemo[i]]
          local rel = getuint(f)
          if rel >= 0 and rel < #s then s.release = rel + 1 end
          s.setting = getuint(f)
        end
      end
    end
  end
  blockTable.SEQUENCES = function (t, ver)
    if ver == 1 then
      error("BLOCK VERSION IS NOT IMPLEMENTED")
      return
    end
    if ver == 2 then
      error("BLOCK VERSION IS NOT IMPLEMENTED")
      return
    end
    readSeqNew("APU")(t, ver)
  end
  blockTable.SEQUENCES_VRC6 = function (t, ver)
    if ver < 4 then
      error("BLOCK VERSION IS NOT IMPLEMENTED")
      return
    end
    readSeqNew("VRC6")(t, ver)
  end
  
  local readSeqExt = function (chipName)
    local seqt = "seq" .. chipName
    return function (t, ver)
      for i = 1, getint(f) do
        local id = getuint(f) + 1
        local seqType = getuint(f) + 1
        local count = getuchar(f)
        local s = {id = id}
        local loop = getint(f)
        if loop >= 0 and loop < count then s.loop = loop + 1 end
        local rel = getint(f)
        if rel >= 0 and rel < count then s.release = rel + 1 end
        s.setting = getuint(f)
        for j = 1, count do s[#s + 1] = getchar(f) end
        ftm[seqt][seqType][id] = s
      end
    end
  end
  blockTable.SEQUENCES_N163 = readSeqExt("N163")
  blockTable.SEQUENCES_S5B = readSeqExt("S5B")
  
  blockTable.FRAMES = function (t, ver)
    if ver == 1 then
      error("BLOCK VERSION IS NOT IMPLEMENTED")
      return
    end
    for i, v in ipairs(t.track) do
      local framecount = getuint(f)
      local speed = getuint(f)
      if ver == 3 then
        v.tempo, v.speed = getint(f), speed
      else
        if speed < 20 then
          v.tempo, v.speed = t.machine == "PAL" and 125 or 150, speed
        else
          v.tempo, v.speed = speed, 6
        end
      end
      v.rows = getuint(f)
      for j = 1, framecount do
        v.frame[j] = {}
        for p = 1, t.param.chcount do v.frame[j][p] = getuchar(f) + 1 end
      end
    end
  end
  
  blockTable.PATTERNS = function (t, ver)
    if ver == 1 then
      t.track[1].rows = getint(f)
    end
    while f:seek() ~= currentPos + blockSize do
      local tr = t.track[1 + (ver > 1 and getint(f) or 0)]
      local c = getint(f) + 1
      local cType = t:getTrackChs()[c]
      local p = getint(f) + 1
      for i = 1, getint(f) do
        local r = (t.version == 0x200 and getchar(f) or getint(f)) + 1
        if not tr.pattern[c][p] then tr.pattern[c][p] = {} end
        if not tr.pattern[c][p][r] then tr.pattern[c][p][r] = {} end
        local row = tr.pattern[c][p][r]
        row.note, row.oct, row.inst, row.vol, row.fx = getchar(f), getchar(f), getchar(f), getchar(f), {}
        for j = 1, t.version == 0x200 and 1 or tr.maxeffect[c] do
          local name, param = getuchar(f), getuchar(f)
          if ver < 3 then
            if name == FX.PORTAOFF then
              name, param = FX.PORTAMENTO, 0
            elseif name == FX.PORTAMENTO and param < 0xFF then
              param = param + 1
            end
          end
          if name ~= 0 then row.fx[j] = {name = name, param = param} end
        end
        if row.vol > 0x10 then row.vol = 0x0F end
        if t.version == 0x200 then
          if row.fx[1] and row.fx[1].name == FX.SPEED and row.fx[1].param < 20 then
            row.fx[1].param = row.fx[1].param + 1
          end
          row.vol = row.vol == 0 and 0x10 or (row.vol - 1) % 0x10
          if row.note == 0 then row.inst = 0x40 end
        end
        if cType[1] == CHIP.N163 then for i = 1, 4 do
          if row.fx[i] and row.fx[i].name == FX.SAMPLE_OFFSET then
            row.fx[i].name = FX.N163_WAVE_BUFFER
          end
        end end
        if ver == 3 then for i = 1, 4 do if row.fx[i] then
          if cType[1] == CHIP.VRC7 then
            if row.fx[i].name == FX.PORTA_DOWN then
              row.fx[i].name = FX.PORTA_UP
            elseif row.fx[i].name == FX.PORTA_UP then
              row.fx[i].name = FX.PORTA_DOWN
            end
          elseif cType[1] == CHIP.FDS then
            if row.fx[i].name == FX.PITCH then
              row.fx[i].param = (0x100 - row.fx[i].param) % 0x100
            end
          end
        end end end
        if ver < 5 and cType[1] == CHIP.FDS then
          row.oct = math.min(row.oct + 2, 7)
        end
      end
    end
  end
  
  blockTable["DPCM SAMPLES"] = function (t, ver)
    for i = 1, getuchar(f) do
      local id = getuchar(f) + 1
      local size = getint(f)
      t.dpcm[id] = {name = f:read(size)}
      size = getint(f)
      t.dpcm[id].compressed = f:read(size)
    end
  end
  
  blockTable.COMMENTS = function (t, ver)
    t.comment.open = getint(f) ~= 0
    t.comment.str = getstr(f)
  end
  
  blockTable.DETUNETABLES = function (t, ver)
    if not t.detune then t.detune = {} end
    for i = 1, getuchar(f) do
      t.detune[i] = {}
      for j = 1, getuchar(f) do
        local n = getuchar(f) + 1
        t.detune[i][n] = getint(f)
      end
    end
  end
  
  blockTable.GROOVES = function (t, ver)
    if not t.groove then t.groove = {} end
    for i = 1, getuchar(f) do
      local id = getuchar(f) + 1
      t.groove[id] = {}
      for j = 1, getuchar(f) do
        local c = getuchar(f)
        table.insert(t.groove[id], c)
      end
    end
    assert(getuchar(f) == #t.track, "Track count mismatch in GROOVES block")
    for _, tr in ipairs(t.track) do
      tr.groove = getuchar(f) ~= 0
    end
  end
  
  blockTable.BOOKMARKS = function (t, ver)
    if not t.bookmark then
      t.bookmark = {}
      for i = 1, #t.track do t.bookmark[i] = {} end
    end
    for i = 1, getint(f) do
      local tr = getuchar(f) + 1
      local bm = {highlight = {}}
      bm.frame = getuchar(f) + 1
      bm.row = getuchar(f) + 1
      bm.highlight[1] = getint(f)
      bm.highlight[2] = getint(f)
      bm.persist = getuchar(f) ~= 0
      bm.name = getstr(f)
      table.insert(t.bookmark[tr], bm)
    end
  end
  
  while true do
    local str = string.gsub(f:read(16), "\0", "")
    if str == "END" then break
    else
      local blockVer = getint(f)
      blockSize = getint(f)
      currentPos = f:seek()
      if blockTable[str] then blockTable[str](ftm, blockVer)
      else print("Loader for " .. str .. " block is not implemented") end
      f:seek("set", currentPos + blockSize)
    end
  end
  
  local seqMap = {[1] = "seqAPU", [2] = "seqVRC6", [5] = "seqN163", [6] = "seqS5B"}
  for _, ins in pairs(ftm.inst) do for i = 1, 5 do
    if ins.seq and ins.seq[i] and seqMap[ins.instType] then
      ins.seq[i] = ftm[seqMap[ins.instType]][i][ins.seq[i]]
    end
  end end
  
  f:close()
  return ftm
end

function FTM:saveFTM (name)
  local out = assert(io.open(name, "wb"))
  out:write("FamiTracker Module")
  out:write(intstr(self.version)) -- version

  local writeblock = function (f)
    if type(f) ~= "function" then error("INVALID BLOCK FUNCTION") end
    local block = f(self)
    if not block then return end
    out:write(pad0(block.name, 16))
    out:write(intstr(block.version))
    out:write(intstr(#block.chunk))
    out:write(block.chunk)
  end

  local saveparams = function (ftm)
    local chunk = string.char(ftm.param.chip) .. intstr(ftm:getChCount()) .. intstr(
      ftm.param.machine == "PAL" and 1 or 0,
      ftm.param.rate,
      ftm.param.newVibrato == true and 1 or 0,
      ftm.param.highlight[1],
      ftm.param.highlight[2]
    )
    if ftm:hasChip(CHIP.N163) then chunk = chunk .. intstr(ftm.param.namcoCh) end
    chunk = chunk .. intstr(ftm.param.FxxSplit)
    return {name = "PARAMS", version = 6, chunk = chunk}
  end

  local saveinfo = function (ftm)
    return {name = "INFO", version = 1, chunk = pad0(ftm.info.title, 32) .. pad0(ftm.info.author, 32) .. pad0(ftm.info.copyright, 32)}
  end

  local saveheader = function (ftm)
    local chunk = string.char(#ftm.track - 1)
    for _, v in ipairs(ftm.track) do chunk = chunk .. (v.title or "New song") .. "\x00" end
    for i = 1, ftm.param.chcount do
      chunk = chunk .. string.char(i - 1)
      for _, v in ipairs(ftm.track) do chunk = chunk .. string.char((v.maxeffect[i] - 1) or 0) end
    end
    return {name = "HEADER", version = 3, chunk = chunk}
  end

  local saveinst = function (ftm)
    local writeInst = function (id)
      local chunk = ""
      local ins = ftm.inst[id]
      
      local instSeq = function ()
        chunk = intstr(5)
        for i = 1, 5 do
          chunk = chunk .. (ins.seq[i] and "\x01" .. string.char(ins.seq[i].id - 1) or "\x00\x00")
        end
      end
      local inst2A03 = function ()
        instSeq()
        for i = 1, 96 do
          local d = ins.dpcm[i]
          chunk = chunk .. (d and string.char(d.id, d.pitch, d.delta or 0xFF) or "\x00\x00\xFF")
        end
      end
      local instVRC7 = function ()
        chunk = intstr(ins.patch) .. string.char(table.unpack(ins.custom, 1, 8))
      end
      local instFDS = function ()
        chunk = string.char(table.unpack(ins.wave, 1, 64)) .. string.char(table.unpack(ins.mod, 1, 32))
        chunk = chunk .. intstr(ins.FMrate, ins.FMdepth, ins.FMdelay)
        for i = 1, 3 do
          local s = ins.seq[i] or {}
          chunk = chunk .. string.char(#s) .. intstr((s.loop or 0) - 1, (s.release or 0) - 1, s.mode or 0)
          for _, x in ipairs(s) do chunk = chunk .. string.char(x >= 0 and x or x + 0x100) end
        end
      end
      local instN163 = function ()
        instSeq()
        local m = {}
        for _, v in pairs(ins.wave) do m[#m + 1] = #v end
        m = math.min(table.unpack(m))
        chunk = chunk .. intstr(m, ins.wavePos, #ins.wave)
        for _, v in ipairs(ins.wave) do
          chunk = chunk .. string.char(table.unpack(v, 1, m))
        end
      end
      
      local f = {inst2A03, instSeq, instVRC7, instFDS, instN163, instSeq}
      assert(f[ins.instType], "Unknown instrument type")
      f[ins.instType]()
      return intstr(id - 1) .. string.char(ins.instType) .. chunk .. intstr(#ins.name) .. ins.name
    end
    
    local chunk = intstr(size(ftm.inst))
    for k in pairs(ftm.inst) do
      chunk = chunk .. writeInst(k)
    end
    return {name = "INSTRUMENTS", version = 6, chunk = chunk}
  end

  local saveseq = function (chipName) return function (ftm)
    local chunk = ""
    local extra = ""
    local seqcount = 0
    for i = 1, 5 do for _, v in pairs(ftm["seq" .. chipName][i]) do
      seqcount = seqcount + 1
      chunk = chunk .. intstr(v.id - 1, i - 1) .. string.char(#v) .. intstr((v.loop or 0) - 1)
      local seqstr = ""
      for _, x in ipairs(v) do seqstr = seqstr .. string.char(x >= 0 and x or x + 0x100) end
      if chipName == "N163" or chipName == "S5B" then
        chunk = chunk .. intstr((v.release or 0) - 1, v.mode or 0) .. seqstr
      else
        chunk = chunk .. seqstr
        extra = extra .. intstr((v.release or 0) - 1, v.mode or 0)
      end
    end end
    local name = "SEQUENCES" .. (chipName == "APU" and "" or "_" .. chipName)
    return {name = name, version = 6, chunk = intstr(seqcount) .. chunk .. extra}
  end end

  local saveframe = function (ftm)
    local chunk = ""
    for _, v in ipairs(ftm.track) do
      local frame = intstr(#v.frame, v.speed, v.tempo, v.rows)
      for _, k in ipairs(v.frame) do for _, p in ipairs(k) do frame = frame .. string.char(p - 1) end end
      chunk = chunk .. frame
    end
    return {name = "FRAMES", version = 3, chunk = chunk}
  end

  local savepattern = function (ftm)
    local chunk = ""
    for k, t in ipairs(ftm.track) do for i = 1, ftm.param.chcount do for k2, p in pairs(t.pattern[i]) do
      local pattern = intstr(k - 1, i - 1, k2 - 1, size(p))
      for r, n in pairs(p) do if r ~= "id" then
        pattern = pattern .. intstr(r - 1) .. string.char(n.note, n.oct, n.inst, n.vol)
        for j = 1, t.maxeffect[i] do
          pattern = pattern .. (n.fx[j] and string.char(n.fx[j].name, n.fx[j].param) or "\x00\x00")
        end
      end end
      chunk = chunk .. pattern
    end end end
    return {name = "PATTERNS", version = 5, chunk = chunk}
  end

  local savedpcm = function (ftm)
    if not ftm.dpcm or not next(ftm.dpcm) then return end
    local chunk = string.char(size(ftm.dpcm))
    for k, v in pairs(ftm.dpcm) do
      local samp = v.compressed and intstr(#v.compressed) .. v.compressed or intstr(#v) .. string.char(table.unpack(v))
      chunk = chunk .. string.char(k - 1) .. intstr(#v.name) .. v.name .. samp
    end
    return {name = "DPCM SAMPLES", version = 1, chunk = chunk}
  end
  
  local savecomment = function (ftm)
    local chunk = intstr(ftm.comment.open and 1 or 0) .. ftm.comment.str .. "\0"
    return {name = "COMMENTS", version = 1, chunk = chunk}
  end

  local savedetune = function (ftm)
    if not ftm.detune or not next(ftm.detune) then return end
    local chunk = ""
    for i = 1, 6 do if ftm.detune[i] and size(ftm.detune[i]) > 0 then -- chips
      local detune = string.char(i - 1, size(ftm.detune[i]))
      for k, v in pairs(ftm.detune[i]) do detune = detune .. string.char(k - 1) .. intstr(v) end
      chunk = chunk .. detune
    end end
    return {name = "DETUNETABLES", version = 1, chunk = chunk}
  end

  local savegroove = function (ftm)
    if not ftm.groove or not next(ftm.groove) then return end
    local chunk = string.char(size(ftm.groove))
    for k, v in pairs(ftm.groove) do chunk = chunk .. string.char(k - 1, #v) .. string.char(table.unpack(v)) end
    chunk = chunk .. string.char(#ftm.track)
    for _, t in ipairs(ftm.track) do chunk = chunk .. string.char(t.groove == true and 1 or 0) end
    return {name = "GROOVES", version = 1, chunk = chunk}
  end
  
  local savebookmark = function (ftm)
    if not ftm.bookmark or not next(ftm.bookmark) then return end
    local chunk = ""
    local count = 0
    for tr, k in pairs(ftm.bookmark) do
      for _, v in pairs(k) do
        local bm = string.char(tr - 1, v.frame - 1, v.row - 1)
        bm = bm .. intstr(v.highlight[1], v.highlight[2])
        bm = bm .. string.char(v.persist and 1 or 0) .. v.name .. "\0"
        chunk = chunk .. bm
        count = count + 1
      end
    end
    return {name = "BOOKMARKS", version = 1, chunk = intstr(count) .. chunk}
  end

  writeblock(saveparams)
  writeblock(saveinfo)
  writeblock(saveheader)
  writeblock(saveinst)
  for _, v in ipairs({"APU", "VRC6", "N163", "S5B"}) do
    if self:hasChip(CHIP[v]) then writeblock(saveseq(v)) end
  end
  writeblock(saveframe)
  writeblock(savepattern)
  writeblock(savedpcm)
  writeblock(savecomment)
  writeblock(savedetune)
  writeblock(savegroove)
  writeblock(savebookmark)
  
  out:write("END")
  out:close()
end

return FTM