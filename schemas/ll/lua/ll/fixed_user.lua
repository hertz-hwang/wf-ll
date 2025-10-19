--- 快捷调整用户固定词

-- 内嵌 snow.lua 的功能
local snow = {
  kRejected = 0,
  kAccepted = 1,
  kNoop = 2,
  kVoid = "kVoid",
  kGuess = "kGuess",
  kSelected = "kSelected",
  kConfirmed = "kConfirmed",
  kNull = "kNull",     -- 空節點
  kScalar = "kScalar", -- 純數據節點
  kList = "kList",     -- 列表節點
  kMap = "kMap",       -- 字典節點
  kShift = 0x1,
  kLock = 0x2,
  kControl = 0x4,
  kAlt = 0x8,
}

--- 取出输入中当前正在翻译的一部分
---@param context Context
function snow.current(context)
  local segment = context.composition:toSegmentation():back()
  if not segment then
    return nil
  end
  return context.input:sub(segment.start + 1, segment._end)
end

---格式化 Info 日志
---@param format string|number
function snow.infof(format, ...)
  log.info(string.format(format, ...))
end

---格式化 Warn 日志
---@param format string|number
function snow.warnf(format, ...)
  log.warning(string.format(format, ...))
end

---格式化 Error 日志
---@param format string|number
function snow.errorf(format, ...)
  log.error(string.format(format, ...))
end

---@param s string
---@param i number
---@param j number
function snow.sub(s, i, j)
  i = i or 1
  j = j or -1
  if i < 1 or j < 1 then
    local n = utf8.len(s)
    if not n then return "" end
    if i < 0 then i = n + 1 + i end
    if j < 0 then j = n + 1 + j end
    if i < 0 then i = 1 elseif i > n then i = n end
    if j < 0 then j = 1 elseif j > n then j = n end
  end
  if j < i then return "" end
  i = utf8.offset(s, i)
  j = utf8.offset(s, j + 1)
  if i and j then
    return s:sub(i, j - 1)
  elseif i then
    return s:sub(i)
  else
    return ""
  end
end

---@param candidate Candidate
---@param proxy string
function snow.prepare(candidate, proxy, normal)
  local proxy_segment = proxy:sub(1, candidate._end - candidate._start);
  candidate._end = candidate._start + proxy_segment:gsub("[ ?]", ""):len()
  if not normal then
    candidate.quality = candidate.quality + 1
  end
  -- candidate.comment = ("%s, %s, %d, %d"):format(proxy, proxy_segment, candidate._start, candidate._end)
  return candidate
end

---@param path string
function snow.table_from_tsv(path)
  ---@type table<string, string>
  local result = {}
  local file = io.open(path, "r")
  if not file then
    return result
  end
  for line in file:lines() do
    ---@type string, string
    local character, content = line:match("([^\t]+)\t([^\t]+)")
    if not content or not character then
      goto continue
    end
    result[character] = content
    ::continue::
  end
  file:close()
  return result
end

-- 以下是原有的 fixed_user.lua 代码
local fixed_user_processor = {}

---@class Record
---@field code string
---@field index integer
---@field cands string[]
---@field isFixed boolean[]

---@class FixedUserEnv: Env
---@field fixed_user_db LevelDb
---@field record Record
---@field page_size integer
---@field select_keys table<string, integer>
---@field trigger_key KeyEvent
---@field finish_key KeyEvent
---@field up_key KeyEvent
---@field down_key KeyEvent
---@field fix_key KeyEvent
---@field erase_key KeyEvent
---@field quick_code_indicator string
---@field linglong_quality_threshold integer
---@field custom_phrases_indicator string
---@field custom_quality_threshold integer

---@type table<string, LevelDb>
FixedUserDbPool = FixedUserDbPool or {}

local function getFixedUserDb(schema_name)
  local dbname = schema_name .. "_fixed_user"
  FixedUserDbPool[dbname] = FixedUserDbPool[dbname] or LevelDb(dbname)
  local db = FixedUserDbPool[dbname]
  if db and not db:loaded() then
    db:open()
  end
  return db
end

-- 关闭所有数据库连接
local function closeAllFixedUserDb()
  for dbname, db in pairs(FixedUserDbPool) do
    if db and db:loaded() then
      db:close()
    end
  end
  FixedUserDbPool = {}
end

---@param r Record
---@return string
local function showRecord(r)
  ---@type string[]
  local result = {}
  for k, text in pairs(r.cands) do
    if r.isFixed[k] then
      result[k + 1] = "★" .. text
    else
      result[k + 1] = text
    end
  end
  return table.concat(result, " ")
end

---@param db UserDb
---@param r Record
local function FixedUserDbUpdate(db, r)
  local _fixed_string_array = {}
  local last_fixed_index = 0
  for k, text in pairs(r.cands) do
    if r.isFixed[k] then
      _fixed_string_array[k + 1] = text
      last_fixed_index = math.max(k, last_fixed_index) + 1
    else
      _fixed_string_array[k + 1] = "∅"
    end
  end
  local fixed_string_array = {}
  local i = 1
  for _, text in ipairs(_fixed_string_array) do
    i = i + 1
    if i - 1 > last_fixed_index then
      break
    end
    table.insert(fixed_string_array, text)
  end
  local db_key = string.format("%s\t0", r.code)
  local fixed_string = table.concat(fixed_string_array, "|")
  ---@type integer
  local t = 0
  for _, v in db:query(db_key):iter() do
    t = string.match(v, "t=(%d)")
  end
  db:update(db_key, string.format("c=0 d=%s t=%d", fixed_string, t + 1))
end

---@param db LevelDb
---@param text string
local function FixedUserDbErase(db, text)
  db:erase(string.format("%s\t0", text))
end

---@param db LevelDb
---@param code string
---@param length integer
---@return boolean[]
local function UserDbEntryToIsFixed(db, code, length)
  ---@type boolean[]
  local result = {}
  ---@type string?
  local value = nil
  for _, v in db:query(string.format("%s\t0", code)):iter() do
    value = v:match("d=(.+) t")
  end
  local i = 1
  if value then
    for text in value:gmatch("[^|]+") do
      i = i + 1
      if text == "∅" then
        result[i - 1] = false
      else
        result[i - 1] = true
      end
    end
  end
  for j = i, length - 1 do
    result[j] = false
  end
  return result
end

---@param db LevelDb
---@param code string
---@return string[]
local function FixedUserDbQuery(db, code)
  ---@type string[]
  local result = {}
  ---@type string?
  local value = nil
  for _, v in db:query(string.format("%s\t0", code)):iter() do
    value = v:match("d=(.+) t")
  end
  local i = 1
  if value then
    for text in value:gmatch("[^|]+") do
      i = i + 1
      result[i - 1] = text
    end
  end
  for k, v in ipairs(result) do
  end
  return result
end

---@param env FixedUserEnv
function fixed_user_processor.init(env)
  env.fixed_user_db = getFixedUserDb(env.engine.schema.schema_id)
  local context = env.engine.context
  env.record = {
    code = "",
    index = 0,
    cands = {},
    isFixed = {},
  }
  ---@param ctx Context
  local function clear(ctx)
    ctx:set_property("adjusting", "")
  end
  env.engine.context.select_notifier:connect(clear)
  env.engine.context.commit_notifier:connect(clear)
  local config = env.engine.schema.config
  local page_size = config:get_value("menu/page_size")
  if page_size then
    env.page_size = page_size:get_int() or 10
  else
    env.page_size = 10
  end
  env.select_keys = {}
  local alternative_select_keys = config:get_string("menu/alternative_select_keys")
  if alternative_select_keys then
    for i = 1, #alternative_select_keys do
      local key = alternative_select_keys:sub(i, i)
      env.select_keys[key] = i - 1
    end
  else
    env.select_keys = {
      ["1"] = 0,
      ["2"] = 1,
      ["3"] = 2,
      ["4"] = 3,
      ["5"] = 4,
      ["6"] = 5,
      ["7"] = 6,
      ["8"] = 7,
      ["9"] = 8,
      ["0"] = 9,
    }
  end
  local trigger_key = config:get_value("fixed_user/trigger_key")
  if trigger_key then
    env.trigger_key = KeyEvent(trigger_key:get_string())
  else
    env.trigger_key = KeyEvent("[")
  end
  local finish_key = config:get_value("fixed_user/finish_key")
  if finish_key then
    env.finish_key = KeyEvent(finish_key:get_string())
  else
    env.finish_key = KeyEvent("Return")
  end
  local up_key = config:get_value("fixed_user/up_key")
  if up_key then
    env.up_key = KeyEvent(up_key:get_string())
  else
    env.up_key = KeyEvent("Control+k")
  end
  local down_key = config:get_value("fixed_user/down_key")
  if down_key then
    env.down_key = KeyEvent(down_key:get_string())
  else
    env.down_key = KeyEvent("Control+j")
  end
  local fix_key = config:get_value("fixed_user/fix_key")
  if fix_key then
    env.fix_key = KeyEvent(fix_key:get_string())
  else
    env.fix_key = KeyEvent("Control+t")
  end
  local erase_key = config:get_value("fixed_user/erase_key")
  if erase_key then
    env.erase_key = KeyEvent(erase_key:get_string())
  else
    env.erase_key = KeyEvent("Control+x")
  end
end

---@param key_event KeyEvent
---@param env FixedUserEnv
function fixed_user_processor.func(key_event, env)
  local adjusting = env.engine.context:get_property("adjusting") == "true"
  local context = env.engine.context
  local keyName = key_event:repr()
  local keyChar = utf8.char(key_event.keycode)
  local select = env.select_keys[keyChar]
  local modified = key_event:release() or key_event:alt() or key_event:ctrl() or key_event:caps()
  local seg = context.composition:toSegmentation():back()
  if not seg then
    return snow.kNoop
  end
  if key_event:eq(env.trigger_key) then
    context:set_property("adjusting", "true")
    seg.prompt = "操作用户固定词"
    local menu = seg.menu
    local input = snow.current(context)
    if not input then
      return snow.kNoop
    end
    local menu_size = math.min(env.page_size, menu:candidate_count())
    if env.record.code ~= input or #env.record.cands == 0 then
      env.record.code = input
      env.record.cands = {}
      for i = 1, menu_size do
        env.record.cands[i - 1] = menu:get_candidate_at(i - 1).text
      end
      env.record.isFixed = UserDbEntryToIsFixed(env.fixed_user_db, input, menu_size)
    end
    env.record.index = 0
    return snow.kAccepted
  elseif adjusting and key_event:eq(env.finish_key) then
    context:set_property("adjusting", "false")
    context:clear()
    return snow.kAccepted
  elseif not modified and select ~= nil and adjusting then
    seg.prompt = string.format("当前选择：%s", env.record.cands[select])
    env.record.index = select
    return snow.kAccepted
  elseif adjusting and key_event:eq(env.up_key) then
    local index = env.record.index
    if index == 0 then
      return snow.kNoop
    end
    local temp = env.record.cands[index]
    env.record.cands[index] = env.record.cands[index - 1]
    env.record.cands[index - 1] = temp
    env.record.isFixed[index] = false
    env.record.isFixed[index - 1] = false
    env.record.index = index - 1
    seg.prompt = string.format("向上：%s", showRecord(env.record), " ")
    return snow.kAccepted
  elseif adjusting and key_event:eq(env.down_key) then
    local index = env.record.index
    if index == #env.record.cands then
      -- 傻逼 Lua 的 key 是 integer 的表一律当成数组，长度从1开始，真实的长度应 +1
      return snow.kNoop
    end
    local temp = env.record.cands[index]
    env.record.cands[index] = env.record.cands[index + 1]
    env.record.cands[index + 1] = temp
    env.record.isFixed[index] = false
    env.record.isFixed[index + 1] = false
    env.record.index = index + 1
    seg.prompt = string.format("向下：%s", showRecord(env.record), " ")
    return snow.kAccepted
  elseif adjusting and key_event:eq(env.fix_key) then
    env.record.isFixed[env.record.index] = not env.record.isFixed[env.record.index]
    seg.prompt = string.format("固定：%s", showRecord(env.record), " ")
  elseif adjusting and key_event:eq(env.erase_key) then
    env.record.cands = {}
    env.record.isFixed = {}
    seg.prompt = "清空自定义"
    FixedUserDbErase(env.fixed_user_db, env.record.code)
  elseif adjusting and keyName == "space" then
    FixedUserDbUpdate(env.fixed_user_db, env.record)
    local input = snow.current(context)
    context:clear()
    if input then
      context:push_input(input)
      context.composition:toSegmentation():back().prompt = "重载"
    end
    return snow.kAccepted
  end
  return snow.kNoop
end

-- 添加 processor 的 fini 函数
function fixed_user_processor.fini(env)
  if env.fixed_user_db and env.fixed_user_db:loaded() then
    env.fixed_user_db:close()
  end
end

---@param fixed_phrases string[]
---@param unknown_candidates Candidate[]
---@param i number
---@param j number
---@param segment Segment
local function finalize(fixed_phrases, unknown_candidates, i, j, segment)
  -- 输出设为固顶但是没在候选中找到的候选
  -- 因为不知道全码是什么，所以只能做一个 SimpleCandidate
  while fixed_phrases[i] do
    local simple_candidate = Candidate("fixed_user", segment.start, segment._end, fixed_phrases[i], "")
    simple_candidate.comment = "📌 W"  -- 固定标记在前，W在后
    i = i + 1
    yield(simple_candidate)
  end
  -- 输出没有固顶的候选
  for _j, unknown_candidate in ipairs(unknown_candidates) do
    if _j < j then
      goto continue
    end
    yield(unknown_candidate)
    ::continue::
  end
end

local fixed_user_filter = {}

function fixed_user_filter.init(env)
  env.fixed_user_db = getFixedUserDb(env.engine.schema.schema_id)
  
  -- 整合 fix_filter 的配置
  env.quick_code_indicator = env.engine.schema.config:get_string("fixed_user/quick_code_indicator") or "⚡️"
  -- LL_linglong 词库的初始 quality 设置为 100000，用于识别来源
  env.linglong_quality_threshold = 100000
  env.custom_phrases_indicator = env.engine.schema.config:get_string("fixed_user/custom_phrases_indicator") or "👤"
  -- 自定义词库的初始 quality 设置为 10000，用于识别来源
  env.custom_quality_threshold = 10000
end

-- 添加 filter 的 fini 函数
function fixed_user_filter.fini(env)
  if env.fixed_user_db and env.fixed_user_db:loaded() then
    env.fixed_user_db:close()
  end
end

-- 辅助函数：为候选词添加标记（修改为添加到原有comment后面）
local function add_indicator(cand, indicator)
  if not cand.comment or cand.comment == "" then
     cand.comment = indicator
  elseif not cand.comment:find(indicator) then
     -- 如果已有注释但不包含该标记，则添加到注释后面
     cand.comment = cand.comment .. " " .. indicator
  end
  return cand
end

-- 辅助函数：应用快速码标记（修改为添加到原有comment后面）
local function apply_quick_code_markers(cand, env)
  -- 检查候选词是否来自 LL_linglong 词库
  if cand.quality >= env.linglong_quality_threshold then
     cand = add_indicator(cand, env.quick_code_indicator)
  -- 检查候选词是否来自自定义词库
  elseif cand.quality >= env.custom_quality_threshold and cand.quality < env.linglong_quality_threshold then
     cand = add_indicator(cand, env.custom_phrases_indicator)
  end
  return cand
end

---@class CandInt
---@field c Candidate
---@field i number

---@param translation Translation
---@param env FixedUserEnv
function fixed_user_filter.func(translation, env)
  local segment = env.engine.context.composition:toSegmentation():back()
  local input = snow.current(env.engine.context)
  if not segment or not input then
    for candidate in translation:iter() do
      candidate = apply_quick_code_markers(candidate, env)
      yield(candidate)
    end
    return
  end
  local fixed_phrases = FixedUserDbQuery(env.fixed_user_db, input)
  if #fixed_phrases == 0 then
    for candidate in translation:iter() do
      candidate = apply_quick_code_markers(candidate, env)
      yield(candidate)
    end
    return
  end
  ---@type table<string, integer>
  local cand_reverse = {}
  for k, v in ipairs(fixed_phrases) do
    cand_reverse[v] = k
  end
  -- 生成固顶候选
  ---@type Candidate[]
  local unknown_candidates = {}
  ---@type { string: Candidate }
  local known_candidates = {}
  local i = 1
  local j = 1
  -- 总共处理的候选数，多了就不处理了
  local total_candidates = 0
  local max_candidates = 50
  local finalized = false
  ---@type CandInt[]
  local candidates = {}
  local _i = 0
  for _c in translation:iter() do
    _i = _i + 1
    ---@type CandInt
    local e = {
      c = _c,
      i = _i
    }
    table.insert(candidates, e)
  end
  table.sort(candidates, function (a, b)
    local v_a = cand_reverse[a.c.text] or 999
    local v_b = cand_reverse[b.c.text] or 999
    if v_a == v_b then
      return a.i < b.i
    end
    return v_a < v_b
  end)
  for _, _candidate in ipairs(candidates) do
    local candidate = _candidate.c
    local is_fixed = false
    for _, phrase in ipairs(fixed_phrases) do
      if candidate.text == phrase then
        is_fixed = true
        break
      end
    end
    if not is_fixed then
      table.insert(unknown_candidates, candidate)
    end
  end
  for _, _candidate in ipairs(candidates) do
    local candidate = _candidate.c
    snow.errorf("cand: %s", candidate.text)
    total_candidates = total_candidates + 1
    if total_candidates == max_candidates then
      finalize(fixed_phrases, unknown_candidates, i, j, segment)
      finalized = true
      candidate = apply_quick_code_markers(candidate, env)
      yield(candidate)
      goto continue
    elseif total_candidates > max_candidates then
      candidate = apply_quick_code_markers(candidate, env)
      yield(candidate)
      goto continue
    end
    local text = candidate.text
    local is_fixed = false
    -- 对于一个新的候选，要么加入已知候选，要么加入未知候选
    for _, phrase in ipairs(fixed_phrases) do
      if text == phrase then
        known_candidates[phrase] = candidate
        is_fixed = true
        break
      end
    end
    -- 每看过一个新的候选之后，看看是否找到了新的固顶候选，如果找到了，就输出
    local current = fixed_phrases[i]
    snow.errorf("当前候选：%s", candidate.text)
    snow.errorf("当前需要的固定候选：%s", current)
    if current and known_candidates[current] then
      snow.errorf("固定")
      local cand = known_candidates[current]
      cand.type = "fixed_user"
      -- 保留原有的 comment，在后面加上固定标记
      local original_comment = cand.comment or ""
      cand.comment = (original_comment ~= "" and original_comment .. " " or "") .. "📌"
      -- 应用快速码标记
      cand = apply_quick_code_markers(cand, env)
      yield(cand)
      i = i + 1
    end
    if current == "∅" then
      snow.errorf("来")
      local cand = unknown_candidates[j]
      if cand then
        snow.errorf("Why")
        snow.errorf("填空：%s", cand.text)
        -- 应用快速码标记
        cand = apply_quick_code_markers(cand, env)
        yield(cand)
        i = i + 1
        j = j + 1
      end
    end
    ::continue::
  end
  if not finalized then
    -- 修改 finalize 函数调用，使其能够应用快速码标记
    for cand in finalize(fixed_phrases, unknown_candidates, i, j, segment) do
      cand = apply_quick_code_markers(cand, env)
      yield(cand)
    end
  end
end

-- 添加全局 fini 函数
local function global_fini()
  closeAllFixedUserDb()
end

return {
  processor = fixed_user_processor,
  filter = fixed_user_filter,
  fini = global_fini  -- 添加全局 fini 函数
}