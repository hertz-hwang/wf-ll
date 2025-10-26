-- LL Quick Code Filter
-- Copyright (c) 2023, 2024 ksqsf
-- Licensed under GPLv3
--
-- 功能：识别来自 LL_linglong 词库和自定义词库的候选词，在 comment 处添加相应标记

local Top = {}

function Top.init(env)
   env.quick_code_indicator = env.engine.schema.config:get_string("ll/quick_code_indicator") or "🌟"
   -- LL_linglong 词库的初始 quality 设置为 100000，用于识别来源
   env.linglong_quality_threshold = 100000
   env.custom_phrases_indicator = env.engine.schema.config:get_string("ll/custom_phrases_indicator") or "💡"
   -- 自定义词库的初始 quality 设置为 10000，用于识别来源
   env.custom_quality_threshold = 10000
end

function Top.fini(env)
end

-- 辅助函数：为候选词添加标记
local function add_indicator(cand, indicator)
   if not cand.comment or cand.comment == "" then
      cand.comment = indicator
   elseif not cand.comment:find(indicator) then
      -- 如果已有注释但不包含该标记，则添加到注释前面
      cand.comment = indicator .. " " .. cand.comment
   end
   return cand
end

function Top.func(t_input, env)
   for cand in t_input:iter() do
      -- 检查候选词是否来自 LL_linglong 词库
      if cand.quality >= env.linglong_quality_threshold then
         cand = add_indicator(cand, env.quick_code_indicator)
      -- 检查候选词是否来自自定义词库
      elseif cand.quality >= env.custom_quality_threshold and cand.quality < env.linglong_quality_threshold then
         cand = add_indicator(cand, env.custom_phrases_indicator)
      end
      yield(cand)
   end
end

return Top