--[[
Name: chars_cand.lua
Version: 20251005
Author: 荒
Purpose: Character Candidate Module for Rime Input Method
License: 
Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International

---------------------------------------------------------------------------
更新[by Flauver]:
- 20251026: fix bugs.
- 20251125: Adapt the "元书".

Usage:
(1) Place this lua file in the lua directory
(2) Add to engine/processors:
    - lua_processor@chars_cand
(3) Add switch to switches:
    - name: chars_cand
      states: [ 字候选关, 字候选开 ]
      reset: 1 
]]

local bit = (function()
    local bit_ok, bit_ = pcall(require, "bit")
    local bit32_ok, bit32_ = pcall(require, "bit32")
    
    local bit53_ = nil
    local load_func = load or loadstring
    if load_func then
        local bit53_func = load_func("return {bxor = function(a, b) return a ~ b end, band = function(a, b) return a & b end}")
        if bit53_func then bit53_ = bit53_func() end
    end

    local bit = {}
    function bit.bxor(a, b)
        if bit_ok then return bit_.bxor(a, b)
        elseif bit32_ok then return bit32_.bxor(a, b)
        elseif bit53_ then return bit53_.bxor(a, b) end

        local p, c = 1, 0
        while a > 0 and b > 0 do
            local ra, rb = a % 2, b % 2
            if ra ~= rb then c = c + p end
            a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
        end
        return c
    end

    function bit.band(a, b)
        if bit_ok then return bit_.band(a, b)
        elseif bit32_ok then return bit32_.band(a, b)
        elseif bit53_ then return bit53_.band(a, b) end
        local p, c = 1, 0
        while a > 0 and b > 0 do
            local ra, rb = a % 2, b % 2
            if ra + rb > 1 then c = c + p end
            a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
        end
        return c
    end
    return bit
end)()

local userdb = (function()
    local META_KEY_PREFIX = "\001" .. "/"
    local db_pool = setmetatable({}, { __mode = "v" })

    local extends = {}
    function extends:meta_fetch(key) return self._db:fetch(META_KEY_PREFIX .. key) end
    function extends:meta_update(key, value) return self._db:update(META_KEY_PREFIX .. key, value) end
    function extends:empty()
        local da = self._db:query("")
        if da then for key, _ in da:iter() do self._db:erase(key) end end
    end

    local mt = { __index = function(wrapper, key)
        if extends[key] then return extends[key] end
        local real_db = wrapper._db
        local value = real_db[key]
        if type(value) == "function" then return function(_, ...) return value(real_db, ...) end end
        return value
    end}

    local userdb = {}
    function userdb.LevelDb(db_name)
        local key = db_name .. ".userdb"
        local db = db_pool[key] or UserDb(db_name, "userdb")
        db_pool[key] = db
        return setmetatable({_db = db}, mt)
    end
    return userdb
end)()

local chars_cand = {
    version = "v13.3.17",
    RIME_PROCESS_RESULTS = { kRejected = 0, kAccepted = 1, kNoop = 2 }
}

function chars_cand.file_exists(filename)
    local f = io.open(filename, "r")
    if f then io.close(f); return true end
    return false
end

function chars_cand.get_filename_with_fallback(filename)
    local _path = filename:gsub("^/+", "")
    local user_path = rime_api.get_user_data_dir() .. '/' .. _path
    if chars_cand.file_exists(user_path) then return user_path end
    local shared_path = rime_api.get_shared_data_dir() .. '/' .. _path
    if chars_cand.file_exists(shared_path) then return shared_path end
    return nil
end

function chars_cand.is_function_mode_active(context)
    if not context or not context.composition or context.composition:empty() then return false end
    local seg = context.composition:back()
    if not seg then return false end
    return seg:has_tag("number") or seg:has_tag("unicode") or 
           seg:has_tag("calculator") or seg:has_tag("shijian") or seg:has_tag("Ndate")
end

local candidate_db = userdb.LevelDb("lua/chars_cand")

local function calculate_file_hash(filepath)
    local file = io.open(filepath, "rb")
    if not file then return nil end

    local FNV_OFFSET_BASIS = 0x811C9DC5
    local FNV_PRIME = 0x01000193
    local hash = FNV_OFFSET_BASIS
    
    while true do
        local chunk = file:read(4096)
        if not chunk then break end
        for i = 1, #chunk do
            local byte = string.byte(chunk, i)
            hash = bit.bxor(hash, byte)
            hash = (hash * FNV_PRIME) % 0x100000000
            hash = bit.band(hash, 0xFFFFFFFF)
        end
    end

    file:close()
    return string.format("%08x", hash)
end

local candidate_data = {}
candidate_data.status = "pending"
candidate_data.disabled_types = {}
candidate_data.preset_file_path = chars_cand.get_filename_with_fallback("lua/chars_cand/preset_data.txt")
candidate_data.user_override_path = rime_api.get_user_data_dir() .. "/lua/chars_cand/user_data.txt"

local META_KEY = {
    version = "chars_cand_version",
    user_file_hash = "user_candidate_file_hash",
    disabled_types = "disabled_types",
}

function candidate_data.is_disabled(candidate)
    local type = candidate:match("^(..-):") or candidate:match("^(..-)：")
    if not type then return false end
    return candidate_data.disabled_types[type] == true
end

function candidate_data.init_db_from_file(path)
    local file = io.open(path, "r")
    if not file then return end

    for line in file:lines() do
        local value, key = line:match("([^\t]+)\t([^\t]+)")
        if key and value and not candidate_data.is_disabled(value) then
            candidate_db:update(key, value)
        end
    end
    file:close()
end

function candidate_data.ensure_dir_exist(dir)
    local sep = package.config:sub(1, 1)
    dir = dir:gsub([["]], [[\"]])
    if sep == "/" then os.execute('mkdir -p "' .. dir .. '" 2>/dev/null') end
end

function candidate_data.init(config)
    if candidate_data.status ~= "pending" then return end

    local dist = rime_api.get_distribution_code_name() or ""
    local user_lua_dir = rime_api.get_user_data_dir() .. "/lua"
    if dist ~= "hamster" and dist ~= "hamster3" and dist ~= "Weasel" then
        candidate_data.ensure_dir_exist(user_lua_dir)
        candidate_data.ensure_dir_exist(user_lua_dir .. "/chars_cand")
    end

    local disabled_types_list = config:get_list("chars_cand/disabled_types")
    if disabled_types_list then
        for i = 1, disabled_types_list.size do
            local item = disabled_types_list:get_value_at(i - 1)
            if item and #item.value > 0 then
                candidate_data.disabled_types[item.value] = true
            end
        end
    end

    candidate_db:open()
    local needs_rebuild = false

    if candidate_db:meta_fetch(META_KEY.version) ~= chars_cand.version then
        needs_rebuild = true
    end

    local user_file_hash = calculate_file_hash(candidate_data.user_override_path) or ""
    if not needs_rebuild and (candidate_db:meta_fetch(META_KEY.user_file_hash) or "") ~= user_file_hash then
        needs_rebuild = true
    end

    local disabled_keys = {}
    for k, _ in pairs(candidate_data.disabled_types) do table.insert(disabled_keys, k) end
    table.sort(disabled_keys)
    local disabled_types_str = table.concat(disabled_keys, ",")

    if not needs_rebuild and (candidate_db:meta_fetch(META_KEY.disabled_types) or "") ~= disabled_types_str then
        needs_rebuild = true
    end

    if needs_rebuild then
        candidate_db:empty()
        candidate_data.init_db_from_file(candidate_data.preset_file_path)
        candidate_data.init_db_from_file(candidate_data.user_override_path)
        candidate_db:meta_update(META_KEY.version, chars_cand.version)
        candidate_db:meta_update(META_KEY.user_file_hash, user_file_hash)
        candidate_db:meta_update(META_KEY.disabled_types, disabled_types_str)
    end

    candidate_db:close()
    candidate_db:open_read_only()
end

function candidate_data.get_candidate(keys)
    if type(keys) == 'string' then keys = { keys } end
    for _, key in ipairs(keys) do
        if key and key ~= "" then
            local candidate = candidate_db:fetch(key)
            if candidate and #candidate > 0 then return candidate end
        end
    end
    return nil
end

local function update_candidate_prompt(context, env)
    env.current_candidate = nil
    local is_candidate_enabled = context:get_option("chars_cand")
    if not is_candidate_enabled then return end

    local segment = context.composition:back()
    if not segment then return end

    local cand = context:get_selected_candidate() or {}
    if segment.selected_index == 0 then
        env.current_candidate = candidate_data.get_candidate({ context.input, cand.text })
    else
        env.current_candidate = candidate_data.get_candidate(cand.text)
    end

    if env.current_candidate ~= nil and env.current_candidate ~= "" then
        segment.prompt = "〔" .. env.current_candidate .. "〕"
        env.last_prompt = segment.prompt
    elseif segment.prompt ~= "" and env.last_prompt == segment.prompt then
        segment.prompt = ""
        env.last_prompt = segment.prompt
    end
end

local P = {}

function P.init(env)
    local config = env.engine.schema.config
    candidate_data.init(config)
    P.candidate_key = config:get_string("key_binder/candidate_key")

    env.candidate_update_connection = env.engine.context.update_notifier:connect(
        function(context) update_candidate_prompt(context, env) end
    )
end

function P.fini(env)
    if env.candidate_update_connection then
        env.candidate_update_connection:disconnect()
        env.candidate_update_connection = nil
    end
end

function P.func(key, env)
    local context = env.engine.context
    local is_candidate_enabled = context:get_option("chars_cand")
    if not is_candidate_enabled then return chars_cand.RIME_PROCESS_RESULTS.kNoop end

    local segment = context.composition:back()
    if segment and segment:has_tag("paging") then update_candidate_prompt(context, env) end

    if not P.candidate_key or P.candidate_key ~= key:repr() or 
       chars_cand.is_function_mode_active(context) or 
       not env.current_candidate or env.current_candidate == "" then
        return chars_cand.RIME_PROCESS_RESULTS.kNoop
    end

    local commit_txt = env.current_candidate:match("：%s*(.*)%s*") or env.current_candidate:match(":%s*(.*)%s*")
    if commit_txt and #commit_txt > 0 then
        env.engine:commit_text(commit_txt)
        context:clear()
        return chars_cand.RIME_PROCESS_RESULTS.kAccepted
    end

    return chars_cand.RIME_PROCESS_RESULTS.kNoop
end

return P