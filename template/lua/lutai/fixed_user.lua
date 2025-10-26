--- 快捷调整用户固定词

local snow = require "lutai.snow"

local fixed_user_processor = {}

--- 为了跟 librime 的机制相同，Record 的 cands 和 isFixed 是从0开始的
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
---@field fixed_user_memory Memory
---@field block_user_memory Memory
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

--- fixed_user_memory 有两种一对多键值对，一级：{code: word} 和 二级：{code|word: index}
--- commit_count 作为是否生效的标记，正为生效，负为无效

---@param memory Memory
---@param code string
local function FixedUserMemoryReset(memory, code)
  memory:user_lookup(code, false)
  for v_1 in memory:iter_user() do
    memory:update_userdict(v_1, -1, "")
    memory:user_lookup(string.format("%s|%s", code, v_1.text), false)
    for v_2 in memory:iter_user() do
      memory:update_userdict(v_2, -1, "")
    end
  end
end

---@param memory Memory
---@param r Record
local function FixedUserMemoryUpdate(memory, r)
  FixedUserMemoryReset(memory, r.code)
  for k, text in pairs(r.cands) do
    if r.isFixed[k] then
      local entry_1 = DictEntry()
      entry_1.custom_code = r.code .. " "
      entry_1.text = text
      memory:update_userdict(entry_1, 1, "")
      local entry_2 = DictEntry()
      entry_2.custom_code = string.format("%s|%s ", r.code, text)
      entry_2.text = tostring(k)
      memory:update_userdict(entry_2, 1, "")
    end
  end
end

---@param memory Memory
---@param code string
---@param length integer
---@return table<integer, boolean>
local function GetIsFixed(memory, code, length)
  ---@type table<integer, boolean>
  local result = {}
  memory:user_lookup(code, false)
  for v_1 in memory:iter_user() do
    memory:user_lookup(string.format("%s|%s", code, v_1.text), false)
    for v_2 in memory:iter_user() do
      result[tonumber(v_2.text)] = true
    end
  end
  for i = 0, length - 1 do
    if not result[i] then
      result[i] = false
    end
  end
  return result
end

---@param memory Memory
---@param code string
---@return table<integer, string>
local function FixedUserMemoryQuery(memory, code)
  ---@type table<integer, string>
  local result = {}
  local max_index = -1
  memory:user_lookup(code, false)
  for v_1 in memory:iter_user() do
    memory:user_lookup(string.format("%s|%s", code, v_1.text), false)
    for v_2 in memory:iter_user() do
      local index = tonumber(v_2.text)
      if index then
        result[index] = v_1.text
        max_index = math.max(max_index, index)
      end
    end
  end
  for i = 0, max_index do
    if not result[i] then
      result[i] = "∅"
    end
  end
  return result
end

--- block_user_memory 存的是 {code: word}，还是用 commit_count 表示是否生效，正为生效，负为无效

---@param memory Memory
---@param word string
---@param code string
local function BlockUserMemoryUpdate(memory, word, code)
  local entry = DictEntry()
  entry.custom_code = code .. " "
  entry.text = word
  memory:update_userdict(entry, 1, "")
end

---@param memory Memory
---@param code string
---@param cands Candidate[]
---@return Candidate[]
local function BlockCandidates(memory, code, cands)
  ---@type table<string, boolean>
  local blocked = {}
  memory:user_lookup(code, false)
  for v in memory:iter_user() do
    blocked[v.text] = true
  end
  ---@type Candidate[]
  local result = {}
  for _, cand in ipairs(cands) do
    if not blocked[cand.text] then
      table.insert(result, cand)
    end
  end
  return result
end

---@param memory Memory
---@param code string
local function BlockUserMemoryReset(memory, code)
  memory:user_lookup(code, false)
  for v in memory:iter_user() do
    local entry = DictEntry()
    entry.custom_code = v.custom_code
    entry.text = v.text
    memory:update_userdict(entry, -1, "")
  end
end

--- 原生候选池
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
end

---@type fun(word: string, code: string, env: FixedUserEnv)
local addWord

---@param env FixedUserEnv
local function connectMemory(env)
  local path = rime_api:get_user_data_dir()
  local name = env.engine.schema.schema_id
  --- 这个 Memory 不能只操作 user_dict，所以只能弄个伪码表给它
  --- 这个伪码表原来的名字是 lutai.dict.yaml，里面只有 了\ta 这个条目，但编译之后，换了名字也可以用
  local fixed_build_table = io.open(path .. "/build/" .. name .. "_fixed_user.table.bin", "rb")
  if not fixed_build_table then
    local template_table = io.open(path .. "/build_template/abc.table.bin", "rb")
    local build_table = io.open(path .. "/build/" .. name .. "_fixed_user.table.bin", "wb")
    if template_table and build_table then
      build_table:write(template_table:read("a"))
      build_table:close()
      template_table:close()
    end
  else
    fixed_build_table:close()
  end
  local fixed_build_prism = io.open(path .. "/build/" .. name .. "_fixed_user.prism.bin", "rb")
  if not fixed_build_prism then
    local template_prism = io.open(path .. "/build_template/abc.prism.bin", "rb")
    local build_prism = io.open(path .. "/build/" .. name .. "_fixed_user.prism.bin", "wb")
    if template_prism and build_prism then
      build_prism:write(template_prism:read("a"))
      build_prism:close()
      template_prism:close()
    end
  else
    fixed_build_prism:close()
  end
  local schema = Schema(name .. "_fixed_user")
  schema.config:set_string("translator/dictionary", name .. "_fixed_user")
  env.fixed_user_memory = Memory(env.engine, schema)
  local block_build_table = io.open(path .. "/build/" .. name .. "_block_user.table.bin", "rb")
  if not block_build_table then
    local template_table = io.open(path .. "/build_template/abc.table.bin", "rb")
    local build_table = io.open(path .. "/build/" .. name .. "_block_user.table.bin", "wb")
    if template_table and build_table then
      build_table:write(template_table:read("a"))
      build_table:close()
      template_table:close()
    end
  else
    block_build_table:close()
  end
  local block_build_prism = io.open(path .. "/build/" .. name .. "_block_user.prism.bin", "rb")
  if not block_build_prism then
    local template_prism = io.open(path .. "/build_template/abc.prism.bin", "rb")
    local build_prism = io.open(path .. "/build/" .. name .. "_block_user.prism.bin", "wb")
    if template_prism and build_prism then
      build_prism:write(template_prism:read("a"))
      build_prism:close()
      template_prism:close()
    end
  else
    block_build_prism:close()
  end
  local schema = Schema(name .. "_block_user")
  schema.config:set_string("translator/dictionary", name .. "_block_user")
  env.block_user_memory = Memory(env.engine, schema)
end

---@param env FixedUserEnv
function fixed_user_processor.init(env)
  connectMemory(env)
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
  local cands = FixedUserMemoryQuery(env.fixed_user_memory, code)
  local isFixed = GetIsFixed(env.fixed_user_memory, code, 0)
  if cands[0] ~= nil then
    cands[#cands + 1] = word
    isFixed[#isFixed + 1] = true
  else
    cands = {[0] = word}
    isFixed = {[0] = true}
  end
  FixedUserMemoryUpdate(env.fixed_user_memory, {
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
    for k, v in pairs(FixedUserMemoryQuery(env.fixed_user_memory, input)) do
      if v ~= "∅" then
        env.record.cands[k] = menu:get_candidate_at(k).text
      end
    end
    env.record.isFixed = GetIsFixed(env.fixed_user_memory, input, menu_size)
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
    FixedUserMemoryUpdate(env.fixed_user_memory, env.record)
    if env.get_native_candidate_set()[word] then
      -- 只有原生候选才加入屏蔽列表，就是只存在于 fixed_user_memory 的候选直接在 fixed_user_memory 删了就行
      BlockUserMemoryUpdate(env.block_user_memory, word, env.record.code)
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
    FixedUserMemoryReset(env.fixed_user_memory, env.record.code)
    BlockUserMemoryReset(env.block_user_memory, env.record.code)
    return snow.kAccepted
  elseif adjusting and keyName == "space" then
    FixedUserMemoryUpdate(env.fixed_user_memory, env.record)
    local input = snow.current(context)
    context:clear()
    if input then
      context:push_input(input)
      context.composition:toSegmentation():back().prompt = "重载"
    end
    return snow.kAccepted
  elseif not key_event:release() and snow.current(context) and snow.current(context):sub(-#env.add_word_prefix) == env.add_word_prefix then
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
    local input = snow.current(context)
    if not input then
        return snow.kAccepted
    end
    -- 提取编码（去掉末尾的 add_word_prefix）
    local code = input:sub(1, -#env.add_word_prefix - 1)
    context:set_property("code_add", code)
    context:clear()
    return snow.kAccepted
  end
  return snow.kNoop
end

---@param env FixedUserEnv
function fixed_user_processor.fini(env)
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
      yield(candidate)
    end
    return
  end
  local fixed_phrases = index0ToArray(FixedUserMemoryQuery(env.fixed_user_memory, input))
  if #fixed_phrases == 0 then
    for candidate in translation:iter() do
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
  env.set_native_candidate_set(native_cand_set)
  if not finalized then
    finalize(fixed_phrases, unknown_candidates, i, j, unscreened_cands, segment, env)
  end
  for _, candidates in ipairs(BlockCandidates(env.block_user_memory, input, unscreened_cands)) do
    yield(candidates)
  end
  for _, candidate in ipairs(excess_candidates) do
    yield(candidate)
  end
end

return {
  processor = fixed_user_processor,
  filter = fixed_user_filter
}
