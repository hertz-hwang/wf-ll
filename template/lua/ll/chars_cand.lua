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

Usage:
(1) Place this lua file in the lua directory
(2) Add to engine/processors:
    - lua_processor@chars_cand
(3) Add switch to switches:
    - name: chars_cand
      states: [ 字候选关, 字候选开 ]
      reset: 1 
]]

-- ==================== CONFIGURATION CONSTANTS ====================
local DB_KEY_PREFIX = string.char(1) .. "config/"
local DB_USER_FILE_HASH_KEY = "user_config_hash"
local PRESET_DATA_FILE = "lua/chars_cand/preset_data.txt"
local USER_DATA_FILE = "lua/chars_cand/user_data.txt"

-- ==================== CORE MODULE DEFINITION ====================
local core_module = {
    PROCESS_RESULTS = {
        rejected = 0,
        accepted = 1, 
        no_operation = 2,
    }
}

-- ==================== FILE SYSTEM UTILITIES ====================
function core_module.check_file_exists(file_path)
    local file_handle = io.open(file_path, "r")
    if file_handle then
        file_handle:close()
        return true
    end
    return false
end

function core_module.resolve_file_path(relative_path)
    local normalized_path = relative_path:gsub("^/+", "")
    
    -- User data directory (priority)
    local user_dir_path = rime_api.get_user_data_dir() .. '/' .. normalized_path
    if core_module.check_file_exists(user_dir_path) then
        return user_dir_path
    end
    
    -- Shared data directory (fallback)
    local system_dir_path = rime_api.get_shared_data_dir() .. '/' .. normalized_path
    if core_module.check_file_exists(system_dir_path) then
        return system_dir_path
    end
    
    return nil
end

-- ==================== DATA STORAGE MANAGER ====================
local data_manager = {
    db_instance = nil
}

function data_manager.cleanup()
    if data_manager.db_instance and data_manager.db_instance:loaded() then
        collectgarbage()
        local cleanup_result = data_manager.db_instance:close()
        data_manager.db_instance = nil
        return cleanup_result
    end
    return true
end

function data_manager.get_connection(require_write)
    if data_manager.db_instance == nil then 
        data_manager.db_instance = LevelDb("lua/chars_cand") 
    end

    local is_connected = data_manager.db_instance:loaded()
    local need_reconnect = false

    if is_connected and require_write and data_manager.db_instance.read_only then
        need_reconnect = true
    elseif not is_connected then
        need_reconnect = true
    end

    if need_reconnect then
        if is_connected then data_manager.db_instance:close() end
        if require_write then
            data_manager.db_instance:open()
        else
            data_manager.db_instance:open_read_only()
        end
    end

    return data_manager.db_instance
end

-- CRUD Operations
function data_manager.retrieve(key)
    return data_manager.get_connection():fetch(key)
end

function data_manager.store(key, value)
    return data_manager.get_connection(true):update(key, value)
end

function data_manager.clear_all()
    local db_conn = data_manager.get_connection(true)
    local data_iterator = db_conn:query("")
    for key, _ in data_iterator:iter() do
        db_conn:erase(key)
    end
    data_iterator = nil
end

-- Metadata Management
function data_manager.get_metadata(key)
    return data_manager.retrieve(DB_KEY_PREFIX .. key)
end

function data_manager.set_metadata(key, value)
    return data_manager.store(DB_KEY_PREFIX .. key, value)
end

function data_manager.get_user_file_hash()
    return data_manager.get_metadata(DB_USER_FILE_HASH_KEY)
end

function data_manager.set_user_file_hash(hash_value)
    return data_manager.set_metadata(DB_USER_FILE_HASH_KEY, hash_value)
end

-- ==================== DATA INITIALIZATION SYSTEM ====================
local function create_directory_if_needed(dir_path)
    local path_separator = package.config:sub(1, 1)
    dir_path = dir_path:gsub([["]], [[\"]])
    
    if path_separator == "/" then
        local command = 'mkdir -p "' .. dir_path .. '" 2>/dev/null'
        os.execute(command)
    end
end

local function compute_file_signature(file_path)
    local file_handle = io.open(file_path, "rb")
    if not file_handle then return nil end

    local HASH_BASE = 0x811C9DC5
    local HASH_MULTIPLIER = 0x01000193

    -- Bitwise operations (optimized for performance)
    local xor_op, and_op
    if jit and jit.version then
        local bit_ops = require("bit")
        xor_op = bit_ops.bxor
        and_op = bit_ops.band
    else
        xor_op = function(a, b)
            local result, bit_pos = 0, 1
            while a > 0 or b > 0 do
                if a % 2 ~= b % 2 then result = result + bit_pos end
                a, b = math.floor(a/2), math.floor(b/2)
                bit_pos = bit_pos * 2
            end
            return result
        end
        and_op = function(a, b)
            local result, bit_pos = 0, 1
            while a > 0 and b > 0 do
                if a % 2 == 1 and b % 2 == 1 then result = result + bit_pos end
                a, b = math.floor(a/2), math.floor(b/2)
                bit_pos = bit_pos * 2
            end
            return result
        end
    end

    local signature = HASH_BASE
    while true do
        local data_chunk = file_handle:read(4096)
        if not data_chunk then break end
        
        for i = 1, #data_chunk do
            local byte_value = string.byte(data_chunk, i)
            signature = xor_op(signature, byte_value)
            signature = (signature * HASH_MULTIPLIER) % 0x100000000
            signature = and_op(signature, 0xFFFFFFFF)
        end
    end

    file_handle:close()
    return string.format("%08x", signature)
end

local function sync_database_from_file(file_path)
    local file_handle = io.open(file_path, "r")
    if not file_handle then return end

    for data_line in file_handle:lines() do
        local content, identifier = data_line:match("([^\t]+)\t([^\t]+)")
        if content and identifier then
            data_manager.store(identifier, content)
        end
    end
    file_handle:close()
end

local function initialize_data_system()
    -- Check if user data file has changed
    local user_file_path = rime_api.get_user_data_dir() .. "/" .. USER_DATA_FILE
    local current_file_hash = compute_file_signature(user_file_path)
    local user_data_changed = current_file_hash and 
                             current_file_hash ~= data_manager.get_user_file_hash()

    if not user_data_changed then return end

    -- Reload data
    data_manager.clear_all()
    data_manager.set_user_file_hash(current_file_hash or "")

    -- Load data files (user data overrides preset)
    local preset_file_path = core_module.resolve_file_path(PRESET_DATA_FILE)
    if preset_file_path then sync_database_from_file(preset_file_path) end
    sync_database_from_file(user_file_path)

    data_manager.cleanup()
end

-- ==================== HINT PROCESSING ENGINE ====================
local processing_env = {
    current_hint = nil,
    previous_prompt = "",
    update_handler = nil
}

local function find_hint_content(primary_key, fallback_key)
    if not primary_key or primary_key == "" then return nil end
    
    local hint_content = data_manager.retrieve(primary_key)
    if hint_content and #hint_content > 0 then
        return hint_content
    end
    
    return fallback_key and data_manager.retrieve(fallback_key) or nil
end

local function refresh_hint_display(context, env)
    local current_segment = context.composition:back()
    if not current_segment then return end

    local selected_item = context:get_selected_candidate() or {}
    
    -- Determine hint content based on selection state
    if current_segment.selected_index == 0 then
        env.current_hint = find_hint_content(context.input, selected_item.text)
    else
        env.current_hint = find_hint_content(selected_item.text)
    end

    -- Update prompt display
    if env.current_hint and env.current_hint ~= "" then
        current_segment.prompt = "【" .. env.current_hint .. "】"
        env.previous_prompt = current_segment.prompt
    elseif current_segment.prompt ~= "" and env.previous_prompt == current_segment.prompt then
        current_segment.prompt = ""
        env.previous_prompt = current_segment.prompt
    end
end

-- ==================== MAIN PROCESSOR ====================
local MainProcessor = {
    activation_key = nil
}

function MainProcessor.init(env)
    -- Platform-specific directory setup
    local platform = rime_api.get_distribution_code_name() or ""
    local user_lua_path = rime_api.get_user_data_dir() .. "/lua"
    
    if platform ~= "hamster" and platform ~= "Weasel" then
        create_directory_if_needed(user_lua_path)
        create_directory_if_needed(user_lua_path .. "/chars_cand")
    end

    -- Initialize data system
    initialize_data_system()

    -- Get configuration
    MainProcessor.activation_key = env.engine.schema.config:get_string("key_binder/tips_key")

    -- Set up context update listener
    local context = env.engine.context
    env.update_handler = context.update_notifier:connect(function(ctx)
        if ctx:get_option("chars_cand") then
            refresh_hint_display(ctx, env)
        end
    end)
end

function MainProcessor.fini(env)
    data_manager.cleanup()
    if env.update_handler then
        env.update_handler:disconnect()
        env.update_handler = nil
    end
end

function MainProcessor.func(key, env)
    local context = env.engine.context
    local current_segment = context.composition:back()
    
    -- Early exit conditions
    if not context:get_option("chars_cand") or not current_segment then
        return core_module.PROCESS_RESULTS.no_operation
    end

    -- Update hints during paging
    if current_segment:has_tag("paging") then
        refresh_hint_display(context, env)
    end

    -- Handle activation key
    if MainProcessor.activation_key and 
       MainProcessor.activation_key == key:repr() and
       env.current_hint and env.current_hint ~= "" then
        
        local commit_text = env.current_hint:match("：%s*(.*)%s*") or
                          env.current_hint:match(":%s*(.*)%s*")
        if commit_text and #commit_text > 0 then
            env.engine:commit_text(commit_text)
            context:clear()
            return core_module.PROCESS_RESULTS.accepted
        end
    end

    return core_module.PROCESS_RESULTS.no_operation
end

return MainProcessor