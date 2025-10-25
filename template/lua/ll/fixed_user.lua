--- 快捷调整用户固定词
--- By Flauver
--- Version: 0.3.4

-- 从 lutai.snow.lua 整合的必要模块
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

-- 原有的 fixed_user.lua 代码继续从这里开始
local fixed_user_processor = {}

---@param t table<integer, any>
---@retern any[]
local function index0ToArray(t)
  ---@type any[]
  local result = {}
  for k, v in pairs(t) do
    result[k + 1] = v
  end
  return result
end

---@class Record
---@field code string
---@field index integer
---@field cands table<integer, string>
---@field isFixed table<integer, boolean>

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

---@class FixedUserEnv: Env
---@field fixed_user_db LevelDb
---@field block_user_db LevelDb
---@field get_unscreened_candidates fun(): Candidate[]
---@field set_unscreened_candidates fun(cands: Candidate[])
---@field get_native_candidate_set fun(): table<string, boolean>
---@field set_native_candidate_set fun(new_set: table<string, boolean>)
---@field record Record
---@field page_size integer
---@field select_keys table<string, integer>
---@field effect_limit integer
---@field trigger_key KeyEvent
---@field finish_key KeyEvent
---@field up_key KeyEvent
---@field down_key KeyEvent
---@field fix_key KeyEvent
---@field reset_key KeyEvent
---@field delete_key KeyEvent
---@field fixed_tips string
---@field add_word_prefix string
---@field alphabet table<string, boolean>
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

---@param db UserDb
---@param r Record
local function FixedUserDbUpdate(db, r)
  local _fixed_string_array = {}
  local last_fixed_index = 0
  for k, text in pairs(r.cands) do
    if r.isFixed[k] then
      _fixed_string_array[k + 1] = text
      last_fixed_index = math.max(k, last_fixed_index)
    else
      _fixed_string_array[k + 1] = "∅"
    end
  end
  local fixed_string_array = {}
  local i = 0
  for _, text in ipairs(_fixed_string_array) do
    i = i + 1
    if i - 1 > last_fixed_index then
      break
    end
    table.insert(fixed_string_array, text)
  end
  local db_key = string.format("%s\t0", r.code)
  local fixed_string = table.concat(fixed_string_array, "|")
  local t = 0
  for _, v in db:query(db_key):iter() do
    t = string.match(v, "t=(%d+)")
  end
  db:update(db_key, string.format("c=1 d=%s t=%d", fixed_string, t + 1))
end

---@param db LevelDb
---@param text string
local function FixedUserDbReset(db, text)
  local db_key = string.format("%s\t0", text)
  local t = 0
  for _, v in db:query(db_key):iter() do
    t = string.match(v, "t=(%d+)")
  end
  db:update(db_key, string.format("c=1 d=0 t=%d", t + 1))
end

---@param db LevelDb
---@param code string
---@param length integer
---@return table<integer, boolean>
local function GetIsFixed(db, code, length)
  ---@type table<integer, boolean>
  local result = {}
  ---@type string?
  local value = nil
  for _, v in db:query(string.format("%s\t0", code)):iter() do
    value = v:match("d=(.+) t")
  end
  local i = 0
  if value then
    if value == "0" then
      return result
    end
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
---@return table<number, string>
local function FixedUserDbQuery(db, code)
  ---@type table<number, string>
  local result = {}
  ---@type string?
  local value = nil
  for _, v in db:query(string.format("%s\t0", code)):iter() do
    value = v:match("d=(.+) t")
  end
  local i = 0
  if value then
    if value == "0" then
      return result
    end
    for text in value:gmatch("[^|]+") do
      i = i + 1
      result[i - 1] = text
    end
  end
  return result
end

---@type table<string, LevelDb>
BlockUserDbPool = BlockUserDbPool or {}

local function getBlockUserDb(schema_name)
  local dbname = schema_name .. "_block_user"
  BlockUserDbPool[dbname] = BlockUserDbPool[dbname] or LevelDb(dbname)
  local db = BlockUserDbPool[dbname]
  if db and not db:loaded() then
    db:open()
  end
  return db
end

---@param db LevelDb
---@param word string
---@param code string
local function BlockUserDbUpdate(db, word, code)
  local db_key = string.format("%s\t%s", code, word)
  local t = 0
  for _, v in db:query(db_key):iter() do
    t = string.match(v, "t=(%d)")
  end
  db:update(db_key, string.format("c=1 d=1 t=%d", t + 1))
  db:flush()  -- 立即刷新到磁盘
end

---@param db UserDb
---@param code string
---@param cands Candidate[]
---@return Candidate[]
local function BlockCandidates(db, code, cands)
  ---@type Candidate[]
  local result = {}
  for _, cand in ipairs(cands) do
    local db_key = string.format("%s\t%s", code, cand.text)
    ---@type string?
    local enable = nil
    for _, v in db:query(db_key):iter() do
      enable = string.match(v, "d=(%d)")
    end
    if enable ~= "1" then
      table.insert(result, cand)
    end
  end
  return result
end

---@param db UserDb
---@param code string
---@param cands Candidate[]
local function BlockUserDbReset(db, code, cands)
  for _, cand in ipairs(cands) do
    local db_key = string.format("%s\t%s", code, cand.text)
    local t = 0
    for _, v in db:query(db_key):iter() do
      t = string.match(v, "t=(%d)")
    end
    db:update(db_key, string.format("c=1 d=0 t=%d", t + 1))
  end
end

---@type table<string, Candidate[]>
UnscreenedCandidatesPool = UnscreenedCandidatesPool or {}

---@param schema_name string
---@return Candidate[]
local function getUnscreenedCandidates(schema_name)
  UnscreenedCandidatesPool[schema_name] = UnscreenedCandidatesPool[schema_name] or {}
  return UnscreenedCandidatesPool[schema_name]
end

---@param schema_name string
---@param candidates Candidate[]
local function setUnscreenedCandidates(schema_name, candidates)
  UnscreenedCandidatesPool[schema_name] = candidates
end

---@type table<string, table<string, boolean>>
NativeCandidateSetPool = NativeCandidateSetPool or {}

---@param schema_name string
---@return table<string, boolean>
local function getNativeCandidateSet(schema_name)
  NativeCandidateSetPool[schema_name] = NativeCandidateSetPool[schema_name] or {}
  return NativeCandidateSetPool[schema_name]
end

---@param schema_name string
---@param new_set table<string, boolean>
local function setNativeCandidateSet(schema_name, new_set)
  NativeCandidateSetPool[schema_name] = new_set
end

---@param cand Candidate
---@param char string
---@param env FixedUserEnv
local function fixed_tips(cand, char, env)
  ---@type table<string, fun(cand: Candidate)>
  local _switch1 = {
    ["replace"] = function (_cand)
      _cand.comment = char
    end,
    ["append"] = function (_cand)
      _cand.comment = _cand.comment .. char
    end,
    ["off"] = function (_cand)
    end
  }
  _switch1[env.fixed_tips](cand)
end

--- 辅助函数：为候选词添加标记（来自 fixed_filter.lua）
---@param cand Candidate
---@param indicator string
---@return Candidate
local function add_indicator(cand, indicator)
   if not cand.comment or cand.comment == "" then
      cand.comment = indicator
   elseif not cand.comment:find(indicator) then
      -- 如果已有注释但不包含该标记，则添加到注释前面
      cand.comment = indicator .. " " .. cand.comment
   end
   return cand
end

--- 标记候选词来源（来自 fixed_filter.lua）
---@param cand Candidate
---@param env FixedUserEnv
---@return Candidate
local function mark_candidate_source(cand, env)
   -- 检查候选词是否来自 LL_linglong 词库
   if cand.quality >= env.linglong_quality_threshold then
      cand = add_indicator(cand, env.quick_code_indicator)
   -- 检查候选词是否来自自定义词库
   elseif cand.quality >= env.custom_quality_threshold and cand.quality < env.linglong_quality_threshold then
      cand = add_indicator(cand, env.custom_phrases_indicator)
   end
   return cand
end

---@param env FixedUserEnv
local function setDefault(env)
  env.effect_limit = 16
  env.trigger_key = KeyEvent("[")
  env.finish_key = KeyEvent("Return")
  env.up_key = KeyEvent("Control+k")
  env.down_key = KeyEvent("Control+j")
  env.fix_key = KeyEvent("Control+t")
  env.delete_key = KeyEvent("Control+d")
  env.reset_key = KeyEvent("Control+x")
  env.fixed_tips = "replace"
  env.add_word_prefix = "//"
  -- 来自 fixed_filter.lua 的默认配置
  env.quick_code_indicator = "🌟"
  env.linglong_quality_threshold = 100000
  env.custom_phrases_indicator = "💡"
  env.custom_quality_threshold = 10000
end

---@type fun(word: string, code: string, env: FixedUserEnv)
local addWord

---@param env FixedUserEnv
function fixed_user_processor.init(env)
  env.fixed_user_db = getFixedUserDb(env.engine.schema.schema_id)
  env.block_user_db = getBlockUserDb(env.engine.schema.schema_id)
  env.get_unscreened_candidates = function ()
    return getUnscreenedCandidates(env.engine.schema.schema_id)
  end
  env.set_unscreened_candidates = function (cands)
    setUnscreenedCandidates(env.engine.schema.schema_id, cands)
  end
  env.get_native_candidate_set = function ()
    return getNativeCandidateSet(env.engine.schema.schema_id)
  end
  env.set_native_candidate_set = function (new_set)
    setNativeCandidateSet(env.engine.schema.schema_id, new_set)
  end
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
  context:set_property("code_add", "")
  context.property_update_notifier:connect(function (ctx, name)
    if name == "code_add" then
      if ctx:get_property("code_add") ~= "" then
        ctx:set_option("_auto_commit", false)
      else
        ctx:set_option("_auto_commit", true)
      end
    end
  end)
  context.commit_notifier:connect(function (ctx)
    local code = ctx:get_property("code_add")
    if code ~= "" then
      addWord(ctx:get_commit_text(), code, env)
      ctx:set_property("code_add", "")
    end
  end)
  local config = env.engine.schema.config
  local page_size = config:get_value("menu/page_size")
  if page_size then
    env.page_size = page_size:get_int() or 10
  else
    env.page_size = 10
  end
  env.select_keys = {}
  local fixed_user_config = config:get_map("fixed_user")
  local alphabet = config:get_value("speller/alphabet"):get_string() or "abcdefghijklmnopqrstuvwxyz"
  ---@type string?
  local select_keys = nil
  if fixed_user_config then
    local effect_limit = fixed_user_config:get_value("fixed_user/effect_limit")
    if effect_limit then
      env.effect_limit = effect_limit:get_int() or 16
    else
      env.effect_limit = 16
    end
    local trigger_key = fixed_user_config:get_value("trigger_key")
    if trigger_key then
      env.trigger_key = KeyEvent(trigger_key:get_string())
    else
      env.trigger_key = KeyEvent("[")
    end
    local finish_key = fixed_user_config:get_value("finish_key")
    if finish_key then
      env.finish_key = KeyEvent(finish_key:get_string())
    else
      env.finish_key = KeyEvent("Return")
    end
    local up_key = fixed_user_config:get_value("up_key")
    if up_key then
      env.up_key = KeyEvent(up_key:get_string())
    else
      env.up_key = KeyEvent("Control+k")
    end
    local down_key = fixed_user_config:get_value("down_key")
    if down_key then
      env.down_key = KeyEvent(down_key:get_string())
    else
      env.down_key = KeyEvent("Control+j")
    end
    local fix_key = fixed_user_config:get_value("fix_key")
    if fix_key then
      env.fix_key = KeyEvent(fix_key:get_string())
    else
      env.fix_key = KeyEvent("Control+t")
    end
    local delete_key = fixed_user_config:get_value("delete_key")
    if delete_key then
      env.delete_key = KeyEvent(delete_key:get_string())
    else
      env.delete_key = KeyEvent("Control+d")
    end
    local reset_key = fixed_user_config:get_value("reset_key")
    if reset_key then
      env.reset_key = KeyEvent(reset_key:get_string())
    else
      env.reset_key = KeyEvent("Control+x")
    end
    local tips = fixed_user_config:get_value("tips")
    if tips then
      env.fixed_tips = tips:get_string()
    else
      env.fixed_tips = "replace"
    end
    local add_word_prefix = fixed_user_config:get_value("add_word_prefix")
    if add_word_prefix then
      env.add_word_prefix = add_word_prefix:get_string()
    else
      env.add_word_prefix = "//"
    end
    -- 从 fixed_filter.lua 读取配置
    local quick_code_indicator = fixed_user_config:get_value("quick_code_indicator")
    if quick_code_indicator then
      env.quick_code_indicator = quick_code_indicator:get_string()
    else
      env.quick_code_indicator = "⚡️"
    end
    local linglong_quality_threshold = fixed_user_config:get_value("linglong_quality_threshold")
    if linglong_quality_threshold then
      env.linglong_quality_threshold = linglong_quality_threshold:get_int() or 100000
    else
      env.linglong_quality_threshold = 100000
    end
    local custom_phrases_indicator = fixed_user_config:get_value("custom_phrases_indicator")
    if custom_phrases_indicator then
      env.custom_phrases_indicator = custom_phrases_indicator:get_string()
    else
      env.custom_phrases_indicator = "👤"
    end
    local custom_quality_threshold = fixed_user_config:get_value("custom_quality_threshold")
    if custom_quality_threshold then
      env.custom_quality_threshold = custom_quality_threshold:get_int() or 10000
    else
      env.custom_quality_threshold = 10000
    end
    env.alphabet = {}
    local _select_keys = fixed_user_config:get_value("select_keys")
    if _select_keys then
      select_keys = _select_keys:get_string()
    end
  else
    setDefault(env)
  end
  env.alphabet = {}
  for i = 1, #alphabet do
    env.alphabet[alphabet:sub(i, i)] = true
  end
  if not select_keys then
    local _select_keys = config:get_value("menu/alternative_select_keys")
    if _select_keys then
      select_keys = _select_keys:get_string()
    end
  end
  if not select_keys then
    select_keys = "qwertyuiop"
  end
  for i = 1, #select_keys do
    env.select_keys[select_keys:sub(i, i)] = i - 1
  end
end

---@type fun(word: string, code: string, env: FixedUserEnv)
addWord = function (word, code, env)
  local cands = FixedUserDbQuery(env.fixed_user_db, code)
  local isFixed = GetIsFixed(env.fixed_user_db, code, 0)
  if cands[0] ~= nil then
    cands[#cands + 1] = word
    isFixed[#isFixed + 1] = true
  else
    cands = {[0] = word}
    isFixed = {[0] = true}
  end
  FixedUserDbUpdate(env.fixed_user_db, {
    code = code,
    index = 0,
    cands = cands,
    isFixed = isFixed,
  })
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
  if context:get_property("code_add") ~= "" and seg.prompt == "" then
    seg.prompt = string.format("正在加词到 %s", context:get_property("code_add"))
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
    env.record.code = input
    for i = 1, menu_size do
      env.record.cands[i - 1] = menu:get_candidate_at(i - 1).text
    end
    for k, v in pairs(FixedUserDbQuery(env.fixed_user_db, input)) do
      if v ~= "∅" then
        env.record.cands[k] = menu:get_candidate_at(k).text
      end
    end
    env.record.isFixed = GetIsFixed(env.fixed_user_db, input, menu_size)
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
    return snow.kAccepted
  elseif adjusting and key_event:eq(env.delete_key) then
    local word = env.record.cands[env.record.index]
    local input = snow.current(context)
    if not input then
      return snow.kNoop
    end
    ---@type table<integer, string>
    local new_cands = {}
    ---@type table<integer, boolean>
    local new_fixed = {}
    for k, v in pairs(env.record.cands) do
      if k < env.record.index then
        new_cands[k] = v
        new_fixed[k] = env.record.isFixed[k]
      elseif k > env.record.index then
        new_cands[k - 1] = v
        new_fixed[k - 1] = env.record.isFixed[k]
      end
    end
    env.record.cands = new_cands
    env.record.isFixed = new_fixed
    FixedUserDbUpdate(env.fixed_user_db, env.record)
    if env.get_native_candidate_set()[word] then
      BlockUserDbUpdate(env.block_user_db, word, env.record.code)
    end
    context:clear()
    if input then
      context:push_input(input)
      context.composition:toSegmentation():back().prompt = string.format("已删除 %s：%s", word, showRecord(env.record))
    end
    return snow.kAccepted
  elseif adjusting and key_event:eq(env.reset_key) then
    env.record.cands = {}
    env.record.isFixed = {}
    seg.prompt = "清空自定义"
    FixedUserDbReset(env.fixed_user_db, env.record.code)
    BlockUserDbReset(env.block_user_db, env.record.code, env.get_unscreened_candidates())
    return snow.kAccepted
  elseif adjusting and keyName == "space" then
    FixedUserDbUpdate(env.fixed_user_db, env.record)
    local input = snow.current(context)
    context:clear()
    if input then
      context:push_input(input)
      context.composition:toSegmentation():back().prompt = "重载"
    end
    return snow.kAccepted
  -- 先输入编码，再输入 add_word_prefix 来进入加词模式
  elseif not key_event:release() and snow.current(context) then
    local input = snow.current(context)
    if not input then
      return snow.kNoop
    end
    
    -- 检查是否以 add_word_prefix 结尾
    local prefix_len = #env.add_word_prefix
    if #input > prefix_len and input:sub(-prefix_len) == env.add_word_prefix then
      local code = input:sub(1, -prefix_len - 1)  -- 获取前缀前的编码部分
      
      -- 设置操作，允许 BackSpace 和 Escape
      local operation = {
        ["BackSpace"] = true,
        ["Escape"] = true
      }
      
      if env.alphabet[keyChar] then
        context:push_input(keyChar)
      end
      if operation[keyName] then
        return snow.kNoop
      end
      if keyName ~= "space" then
        return snow.kAccepted
      end
      
      -- 按空格确认加词
      context:set_property("code_add", code)
      context:clear()
      seg.prompt = string.format("正在加词到 %s，请输入词语", code)
      return snow.kAccepted
    end
  end
  return snow.kNoop
end

---@param env FixedUserEnv
function fixed_user_processor.fini(env)
  if env.fixed_user_db and env.fixed_user_db:loaded() then
    env.fixed_user_db:close()
  end
  if env.block_user_db and env.block_user_db:loaded() then
    env.block_user_db:close()
  end
end

---@param fixed_phrases string[]
---@param unknown_candidates Candidate[]
---@param i number
---@param j number
---@param unscreened_candidates Candidate[]
---@param segment Segment
---@param env FixedUserEnv
local function finalize(fixed_phrases, unknown_candidates, i, j, unscreened_candidates, segment, env)
  -- 输出设为固顶但是没在候选中找到的候选
  -- 把输出设为固顶的候选但没在候选中找到的候选，加入待筛选的候选列表中
  -- 因为不知道全码是什么，所以只能做一个 SimpleCandidate
  while fixed_phrases[i] do
    local simple_candidate = Candidate("fixed_user", segment.start, segment._end, fixed_phrases[i], "")
    fixed_tips(simple_candidate, "📍", env)
    i = i + 1
    table.insert(unscreened_candidates, simple_candidate)
  end
  -- 输出没有固顶的候选
  -- 把没有固顶的候选，加入待筛选的候选列表中
  for _j, unknown_candidate in ipairs(unknown_candidates) do
    if _j < j then
      goto continue
    end
    table.insert(unscreened_candidates, unknown_candidate)
    ::continue::
  end
end

local fixed_user_filter = {}

function fixed_user_filter.init(env)
  fixed_user_processor.init(env)
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
      -- 应用候选词标记
      candidate = mark_candidate_source(candidate, env)
      yield(candidate)
    end
    return
  end
  local fixed_phrases = index0ToArray(FixedUserDbQuery(env.fixed_user_db, input))
  if #fixed_phrases == 0 then
    for candidate in translation:iter() do
      -- 应用候选词标记
      candidate = mark_candidate_source(candidate, env)
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
  -- local max_candidates = 100
  local total_candidates = 0
  local finalized = false
  ---@type CandInt[]
  local effect_candidates = {}
  ---@type Candidate[]
  local excess_candidates = {}
  local _i = 0
  for _c in translation:iter() do
    _i = _i + 1
    ---@type CandInt
    local e = {
      c = _c,
      i = _i
    }
    if _i - 1 < env.effect_limit then
      table.insert(effect_candidates, e)
    else
      table.insert(excess_candidates, _c)
    end
  end
  -- 排序，避免明明有这个候选，却找不到
  table.sort(effect_candidates, function (a, b)
    local v_a = cand_reverse[a.c.text] or 1024
    local v_b = cand_reverse[b.c.text] or 1024
    if v_a == v_b then
      -- lua 的排序是不稳定的
      return a.i < b.i
    end
    return v_a < v_b
  end)
  -- 提前找到未知的候选，用来填充 ∅
  for _, _candidate in ipairs(effect_candidates) do
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
  ---@type Candidate[]
  local unscreened_cands = {}
  ---@type table<string, boolean>
  local native_cand_set = {}
  for _, _candidate in ipairs(effect_candidates) do
    local candidate = _candidate.c
    total_candidates = total_candidates + 1
    native_cand_set[candidate.text] = true
--    if total_candidates == max_candidates then
--      finalize(fixed_phrases, unknown_candidates, i, j, segment, env)
--      finalized = true
--      yield(candidate)
--      goto continue
--    elseif total_candidates > max_candidates then
--      yield(candidate)
--      goto continue
--    end
    local text = candidate.text
    ---@type Candidate[]
    --local is_fixed = false
    -- 对于一个新的候选，要么加入已知候选，要么加入未知候选
    -- 上面的是原注释，因为已经添加了未知候选了，所以这里就不用加入了
    for _, phrase in ipairs(fixed_phrases) do
      if text == phrase then
        known_candidates[phrase] = candidate
        --is_fixed = true
        break
      end
    end
--    if not is_fixed then
--      table.insert(unknown_candidates, candidate)
--    end
    -- 每看过一个新的候选之后，看看是否找到了新的固顶候选，如果找到了，就输出
    -- 每看过一个新的候选之后，看看是否找到了新的固顶候选，如果找到了，就加入未筛选候选
    local current = fixed_phrases[i]
    if current and known_candidates[current] then
      local cand = known_candidates[current]
      cand.type = "fixed_user"
      fixed_tips(cand, "📌", env)
      table.insert(unscreened_cands, cand)
      i = i + 1
    end
    if current == "∅" then
      local cand = unknown_candidates[j]
      if cand then
        table.insert(unscreened_cands, cand)
        i = i + 1
        j = j + 1
      end
    end
    ::continue::
  end
  env.set_unscreened_candidates(unscreened_cands)
  env.set_native_candidate_set(native_cand_set)
  if not finalized then
    finalize(fixed_phrases, unknown_candidates, i, j, unscreened_cands, segment, env)
  end
  for _, candidates in ipairs(BlockCandidates(env.block_user_db, input, unscreened_cands)) do
    -- 应用候选词标记
    candidates = mark_candidate_source(candidates, env)
    yield(candidates)
  end
  for _, candidate in ipairs(excess_candidates) do
    -- 应用候选词标记
    candidate = mark_candidate_source(candidate, env)
    yield(candidate)
  end
end

return {
  processor = fixed_user_processor,
  filter = fixed_user_filter
}