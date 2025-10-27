-- 顶功处理器
-- 本处理器能够支持所有的规则顶功模式
-- 根据当前编码和新输入的按键来决定是否将当前编码或其一部分的首选顶上屏

local this = {}

-- 定义原本从 snow.lua 导入的常量
local kRejected = 0
local kAccepted = 1
local kNoop = 2
local kVoid = "kVoid"
local kGuess = "kGuess"
local kSelected = "kSelected"
local kConfirmed = "kConfirmed"
local kNull = "kNull"     -- 空節點
local kScalar = "kScalar" -- 純數據節點
local kList = "kList"     -- 列表節點
local kMap = "kMap"       -- 字典節點
local kShift = 0x1
local kLock = 0x2
local kControl = 0x4
local kAlt = 0x8

local strategies = {
  pop = "pop",
  append = "append",
  conditional = "conditional"
}

---@class PoppingConfig
---@field when string
---@field match string
---@field accept string
---@field prefix number
---@field strategy string

---@class PoppingEnv: Env
---@field speller Processor
---@field popping PoppingConfig[]

--- 取出输入中当前正在翻译的一部分
---@param context Context
local function current(context)
  local segment = context.composition:toSegmentation():back()
  if not segment then
    return nil
  end
  return context.input:sub(segment.start + 1, segment._end)
end

---格式化 Error 日志
---@param format string|number
local function errorf(format, ...)
  log.error(string.format(format, ...))
end

---@param env PoppingEnv
function this.init(env)
  env.speller = Component.Processor(env.engine, "", "speller")
  env.engine.context.option_update_notifier:connect(function(ctx, name)
    if name == "buffered" then
      local buffered = ctx:get_option("buffered")
      ctx:set_option("_auto_commit", not buffered)
    end
  end)
  env.engine.context.commit_notifier:connect(function(ctx)
    if ctx:get_option("buffered") then
      ctx:set_option("buffered", false)
    end
  end)
  local config = env.engine.schema.config
  local popping_config = config:get_list("speller/popping")
  if not popping_config then
    return
  end
  ---@type PoppingConfig[]
  env.popping = {}
  for i = 1, popping_config.size do
    local item = popping_config:get_at(i - 1)
    if not item then goto continue end
    local value = item:get_map()
    if not value then goto continue end
    local popping = {
      when = value:get_value("when") and value:get_value("when"):get_string(),
      match = value:get_value("match"):get_string(),
      accept = value:get_value("accept"):get_string(),
      prefix = value:get_value("prefix") and value:get_value("prefix"):get_int(),
      strategy = value:get_value("strategy") and value:get_value("strategy"):get_string()
    }
    if popping.strategy ~= nil and strategies[popping.strategy] == nil then
      errorf("Invalid popping strategy: %s", popping.strategy)
      goto continue
    end
    table.insert(env.popping, popping)
    ::continue::
  end
end

---@param key_event KeyEvent
---@param env PoppingEnv
function this.func(key_event, env)
  local context = env.engine.context
  local buffered = context:get_option("buffered")
  if key_event:release() or key_event:alt() or key_event:ctrl() or key_event:caps() then
    return kNoop
  end
  local incoming = key_event:repr()
  -- 如果输入为空格或数字，代表着作文即将上屏，此时把 kConfirmed 的片段改为 kSelected
  -- 这解决了 https://github.com/rime/home/issues/276 中的不造词问题
  if rime_api.regex_match(incoming, "\\d") or incoming == "space" then
    for _, segment in ipairs(context.composition:toSegmentation():get_segments()) do
      if segment.status == kConfirmed then
        segment.status = kSelected
      end
    end
  end
  -- 取出输入中当前正在翻译的一部分
  local input = current(context)
  if not input then
    return kNoop
  end
  local shape_input = context:get_property("shape_input")
  if shape_input then
    input = input .. shape_input
  end
  
  -- 修复：对于使用 "." 作为编码的方案，移除对 "." 的特殊处理
  -- 原来的代码会屏蔽 "." 输入，现在直接移除这个处理
  
  local incoming_char = utf8.char(key_event.keycode)
  for _, rule in ipairs(env.popping) do
    local when = rule.when
    local success = false
    if when and not context:get_option(when) then
      goto continue
    end
    if not rime_api.regex_match(input, rule.match) then
      goto continue
    end
    if not rime_api.regex_match(incoming_char, rule.accept) then
      goto continue
    end
    -- 如果策略为追加编码，则不执行顶屏直接返回
    if rule.strategy == strategies.append then
      goto finish
    -- 如果策略为条件顶屏，那么尝试先添加编码，如果能匹配到候选就不顶屏
    elseif rule.strategy == strategies.conditional then
      context:push_input(incoming_char)
      if context:has_menu() then
        context:pop_input(1)
        goto finish
      end
      context:pop_input(1)
    end
    if rule.prefix then
      context:pop_input(input:len() - rule.prefix)
    end
    -- 如果当前有候选，则执行顶屏；否则顶功失败，继续执行下一个规则
    if context:has_menu() then
      context:confirm_current_selection()
      if not buffered then
        context:commit()
      end
      success = true
    end
    if rule.prefix then
      context:push_input(input:sub(rule.prefix + 1))
    end
    if success then
      goto finish
    end
    ::continue::
  end
  ::finish::
  -- 大写字母执行完顶屏功能之后转成小写
  if key_event.keycode >= 65 and key_event.keycode <= 90 then
    key_event = KeyEvent(utf8.char(key_event.keycode + 32))
  end
  return env.speller:process_key_event(key_event)
end

return this