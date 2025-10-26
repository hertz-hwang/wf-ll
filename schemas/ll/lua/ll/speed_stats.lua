--[[
-- librime-lua
-- encoding: utf-8

-- Speed Statistics Plugin - Optimized Version
-- Tracks typing speed and character count statistics
---------------------------------------------------------------------------
更新[by Flauver]:
- 20251026: fix bugs.
]]

local M = {}
M.init_flag = false

-- Configuration parameters
M.config = {
    session_timeout = 2000,  -- Session timeout in milliseconds
    save_interval = 60,      -- Save interval in seconds
    min_session_chars = 1,   -- Minimum characters for valid session
    min_session_time = 0.1   -- Minimum session time in seconds
}

-- Data file path
M.stats_file = rime_api.get_user_data_dir() .. "/speed_stats.conf"
M.data_dirty = false
M.last_save_time = os.time()

-- Debug output control
local DEBUG = false
local function debug_print(...)
    if not DEBUG then return end
    local t = {}
    for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end
    log.info("[Speed Stats] " .. table.concat(t, " "))
end

-- Global state management
local gS = {
    -- Current session data
    session_start = 0,           -- Session start time (milliseconds)
    last_commit_time = 0,        -- Last commit time (milliseconds)
    session_chars = 0,           -- Character count in current session
    session_active = false,      -- Whether session is active
    
    -- Previous session data
    last_session_speed = 0,      -- Speed of last session (chars/min)
    last_session_chars = 0,      -- Character count of last session
    last_session_time = 0,       -- Duration of last session (seconds)
    has_previous_session = false,-- Whether previous session data exists
    show_current_speed = false,  -- Whether to show current speed
    
    -- Character count statistics
    char_stats = {
        daily = 0,               -- Today's input count
        monthly = 0,             -- This month's input count
        yearly = 0,              -- This year's input count
        total = 0,               -- Total input count
        last_update = os.date("*t")  -- Last update timestamp
    },
    
    -- Average speed statistics
    avg_speed_stats = {
        daily = {
            total_speed = 0,     -- Sum of all session speeds today
            session_count = 0,   -- Number of sessions today
            last_update = os.date("*t")
        },
        monthly = {
            daily_speeds = {},   -- Daily average speeds for this month
            last_update = os.date("*t")
        },
        yearly = {
            monthly_speeds = {}, -- Monthly average speeds for this year
            last_update = os.date("*t")
        },
        total = {
            yearly_speeds = {},  -- Yearly average speeds
            last_update = os.date("*t")
        }
    }
}

-- Utility function: Safe table serialization
local function serialize_value(v)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        return table.serialize(v)
    else
        return "nil"
    end
end

-- Table serialization function
table.serialize = function(tbl, indent)
    indent = indent or 0
    local spaces = string.rep(" ", indent)
    local lines = {"{"}
    
    -- Sort keys for consistent output
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then return a < b end
        return ta < tb
    end)
    
    -- Serialize each key-value pair
    for _, k in ipairs(keys) do
        local v = tbl[k]
        local key_str = (type(k) == "string") and ("[\"" .. k .. "\"]") or ("[" .. k .. "]")
        local val_str = serialize_value(v)
        table.insert(lines, string.format("    %s%s = %s,", spaces, key_str, val_str))
    end
    
    table.insert(lines, spaces .. "}")
    return table.concat(lines, "\n")
end

-- Save statistics to file with error handling
function M.save_stats(force)
    if not M.data_dirty and not force then return end
    
    local current_time = os.time()
    if force or (current_time - M.last_save_time > M.config.save_interval) then
        local ok, err = pcall(function()
            local file = io.open(M.stats_file, "w")
            if not file then
                error("Cannot open file: " .. M.stats_file)
            end
            
            -- Prepare data for saving
            local data_to_save = {
                char_stats = gS.char_stats,
                last_session_speed = gS.last_session_speed,
                last_session_chars = gS.last_session_chars,
                last_session_time = gS.last_session_time,
                has_previous_session = gS.has_previous_session,
                avg_speed_stats = gS.avg_speed_stats
            }
            
            file:write("return " .. table.serialize(data_to_save) .. "\n")
            file:close()
            M.last_save_time = current_time
            M.data_dirty = false
            
            debug_print("Data saved successfully")
        end)
        
        if not ok then
            log.error("Failed to save statistics: " .. tostring(err))
        end
    end
end

-- Load statistics from file with error handling
function M.load_stats()
    local function load_defaults()
        debug_print("Using default data")
        gS.char_stats.last_update = os.date("*t")
        gS.avg_speed_stats.daily.last_update = os.date("*t")
        gS.avg_speed_stats.monthly.last_update = os.date("*t")
        gS.avg_speed_stats.yearly.last_update = os.date("*t")
        gS.avg_speed_stats.total.last_update = os.date("*t")
    end
    
    -- Try to load saved data
    local ok, data = pcall(function()
        local file = io.open(M.stats_file, "r")
        if not file then return nil end
        file:close()
        return dofile(M.stats_file)
    end)
    
    if not ok or not data then
        load_defaults()
        return
    end
    
    -- Merge loaded data
    if data.char_stats then
        M.merge_stats(gS.char_stats, data.char_stats)
        M.check_and_reset_date_stats(gS.char_stats)
    end
    
    gS.last_session_speed = data.last_session_speed or 0
    gS.last_session_chars = data.last_session_chars or 0
    gS.last_session_time = data.last_session_time or 0
    gS.has_previous_session = data.has_previous_session or false
    
    if data.avg_speed_stats then
        M.merge_stats(gS.avg_speed_stats, data.avg_speed_stats)
    end
    
    debug_print("Data loaded successfully")
end

-- Helper function to merge statistics data
function M.merge_stats(dest, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dest[k]) == "table" then
            M.merge_stats(dest[k], v)
        else
            dest[k] = v
        end
    end
end

-- Check and reset date-based statistics
function M.check_and_reset_date_stats(stats)
    local current_date = os.date("*t")
    local last_date = stats.last_update or current_date
    
    -- Compare dates using string format to avoid table comparison complexity
    local current_str = os.date("%Y-%m-%d", os.time(current_date))
    local last_str = os.date("%Y-%m-%d", os.time(last_date))
    
    -- Reset daily stats if date changed
    if current_str ~= last_str then
        stats.daily = 0
        gS.avg_speed_stats.daily.total_speed = 0
        gS.avg_speed_stats.daily.session_count = 0
        gS.avg_speed_stats.daily.last_update = current_date
    end
    
    -- Reset monthly stats if month changed
    if current_date.month ~= last_date.month or current_date.year ~= last_date.year then
        stats.monthly = 0
        gS.avg_speed_stats.monthly.daily_speeds = {}
        gS.avg_speed_stats.monthly.last_update = current_date
    end
    
    -- Reset yearly stats if year changed
    if current_date.year ~= last_date.year then
        stats.yearly = 0
        gS.avg_speed_stats.yearly.monthly_speeds = {}
        gS.avg_speed_stats.yearly.last_update = current_date
    end
    
    stats.last_update = current_date
    M.data_dirty = true
end

-- Get current time in milliseconds
function M.get_current_time_ms()
    if rime_api and rime_api.get_time_ms then
        return rime_api.get_time_ms()
    else
        return os.time() * 1000
    end
end

-- Update date-based statistics
function M.update_date_stats()
    M.check_and_reset_date_stats(gS.char_stats)
end

-- Update average speed statistics
function M.update_avg_speed_stats(speed)
    local current_date = os.date("*t")
    local date_str = os.date("%Y-%m-%d")
    local month_str = os.date("%Y-%m")
    local year_str = tostring(current_date.year)
    
    -- Update daily average speed
    local daily = gS.avg_speed_stats.daily
    daily.total_speed = daily.total_speed + speed
    daily.session_count = daily.session_count + 1
    daily.last_update = current_date
    
    -- Update monthly average speed
    local monthly = gS.avg_speed_stats.monthly
    local daily_avg = daily.session_count > 0 and math.floor(daily.total_speed / daily.session_count) or 0
    monthly.daily_speeds[date_str] = daily_avg
    monthly.last_update = current_date
    
    -- Update yearly average speed
    local yearly = gS.avg_speed_stats.yearly
    local monthly_total, monthly_count = 0, 0
    for _, speed_val in pairs(monthly.daily_speeds) do
        monthly_total = monthly_total + speed_val
        monthly_count = monthly_count + 1
    end
    local monthly_avg = monthly_count > 0 and math.floor(monthly_total / monthly_count) or 0
    yearly.monthly_speeds[month_str] = monthly_avg
    yearly.last_update = current_date
    
    -- Update total average speed
    local total = gS.avg_speed_stats.total
    local yearly_total, yearly_count = 0, 0
    for _, speed_val in pairs(yearly.monthly_speeds) do
        yearly_total = yearly_total + speed_val
        yearly_count = yearly_count + 1
    end
    local yearly_avg = yearly_count > 0 and math.floor(yearly_total / yearly_count) or 0
    total.yearly_speeds[year_str] = yearly_avg
    total.last_update = current_date
    
    M.data_dirty = true
end

-- Calculate average speed for a given period
function M.calculate_avg_speed(period)
    local stats = gS.avg_speed_stats[period]
    if not stats then return 0 end
    
    if period == "daily" then
        return stats.session_count > 0 and math.floor(stats.total_speed / stats.session_count) or 0
    elseif period == "monthly" then
        local total, count = 0, 0
        for _, speed_val in pairs(stats.daily_speeds) do
            total = total + speed_val
            count = count + 1
        end
        return count > 0 and math.floor(total / count) or 0
    elseif period == "yearly" then
        local total, count = 0, 0
        for _, speed_val in pairs(stats.monthly_speeds) do
            total = total + speed_val
            count = count + 1
        end
        return count > 0 and math.floor(total / count) or 0
    elseif period == "total" then
        local total, count = 0, 0
        for _, speed_val in pairs(stats.yearly_speeds) do
            total = total + speed_val
            count = count + 1
        end
        return count > 0 and math.floor(total / count) or 0
    end
    
    return 0
end

-- Start a new typing session
function M.start_new_session()
    local current_time_ms = M.get_current_time_ms()
    gS.session_start = current_time_ms
    gS.last_commit_time = current_time_ms
    gS.session_chars = 0
    gS.session_active = true
    gS.show_current_speed = false
    debug_print("New session started")
end

-- Manually end current session
function M.end_session_manually()
    if not gS.session_active or gS.session_chars < M.config.min_session_chars then
        return false
    end
    
    local duration_ms = gS.last_commit_time - gS.session_start
    local duration_sec = duration_ms / 1000.0
    
    if duration_sec >= M.config.min_session_time then
        -- Calculate and save session statistics
        gS.last_session_speed = math.floor((gS.session_chars / duration_sec) * 60 + 0.5)
        gS.last_session_chars = gS.session_chars
        gS.last_session_time = duration_sec
        gS.has_previous_session = true
        gS.show_current_speed = true
        
        M.update_avg_speed_stats(gS.last_session_speed)
        M.data_dirty = true
        
        debug_print(string.format("Session ended manually: %d chars/min, %d chars, %.1f sec", 
            gS.last_session_speed, gS.last_session_chars, duration_sec))
    else
        gS.show_current_speed = false
        debug_print("Session too short, not recorded")
    end
    
    gS.session_active = false
    M.save_stats(true)
    
    return true
end

-- Calculate character length (UTF-8 safe)
function M.get_commit_length(text)
    if not text or text == "" then return 0 end
    
    -- Use pcall to safely handle UTF-8 encoding
    local ok, count = pcall(function()
        local cnt = 0
        for _ in utf8.codes(text) do cnt = cnt + 1 end
        return cnt
    end)
    
    return ok and count or #text  -- Fallback to string length if UTF-8 processing fails
end

-- Check if current session is valid
function M.is_valid_session()
    return gS.session_active and 
           gS.session_chars >= M.config.min_session_chars and
           (gS.last_commit_time - gS.session_start) / 1000 >= M.config.min_session_time
end

-- End current session and calculate speed
function M.end_current_session()
    if not M.is_valid_session() then
        gS.session_active = false
        gS.show_current_speed = false
        return false
    end
    
    local duration_ms = gS.last_commit_time - gS.session_start
    local duration_sec = duration_ms / 1000.0
    
    -- Calculate session statistics
    gS.last_session_speed = math.floor((gS.session_chars / duration_sec) * 60 + 0.5)
    gS.last_session_chars = gS.session_chars
    gS.last_session_time = duration_sec
    gS.has_previous_session = true
    gS.show_current_speed = true
    
    -- Update average speed statistics
    M.update_avg_speed_stats(gS.last_session_speed)
    M.data_dirty = true
    
    gS.session_active = false
    
    debug_print(string.format("Session ended: %d chars/min, %d chars, %.1f sec", 
        gS.last_session_speed, gS.last_session_chars, duration_sec))
    
    return true
end

-- Update speed statistics with new input
function M.update_stats(input_length)
    local current_time_ms = M.get_current_time_ms()
    
    -- Check if current session has timed out
    if gS.session_active and (current_time_ms - gS.last_commit_time > M.config.session_timeout) then
        M.end_current_session()
    end
    
    -- Start new session if none is active
    if not gS.session_active then
        M.start_new_session()
    end
    
    -- Update session data
    gS.session_chars = gS.session_chars + input_length
    gS.last_commit_time = current_time_ms
    
    -- Update character count statistics
    M.update_date_stats()
    gS.char_stats.daily = gS.char_stats.daily + input_length
    gS.char_stats.monthly = gS.char_stats.monthly + input_length
    gS.char_stats.yearly = gS.char_stats.yearly + input_length
    gS.char_stats.total = gS.char_stats.total + input_length
    M.data_dirty = true
    
    -- Periodically save data
    M.save_stats()
end

-- Check if session has ended due to timeout
function M.check_session_end()
    local current_time_ms = M.get_current_time_ms()
    
    if gS.session_active and (current_time_ms - gS.last_commit_time > M.config.session_timeout) then
        return M.end_current_session()
    end
    
    return false
end

-- Key event callback handler
local function key_event_callback(ctx, key)
    local key_repr = key:repr()
    
    -- Reset current speed display on typing or backspace
    if key_repr:match("^[a-z]$") or key_repr == "BackSpace" then
        gS.show_current_speed = false
    end
    
    return false
end

-- Format speed statistics summary
function M.format_speed_summary()
    M.check_session_end()
    
    if gS.session_active and gS.session_chars > 0 then
        -- Show current session statistics
        local current_time_ms = M.get_current_time_ms()
        local duration_ms = current_time_ms - gS.session_start
        local duration_sec = duration_ms / 1000.0
        
        local current_speed = 0
        if duration_sec > 0 then
            current_speed = math.floor((gS.session_chars / duration_sec) * 60 + 0.5)
        end
        
        return string.format("Current Speed: %d chars/min\nCharacters: %d\nTime: %.1f sec", 
                           current_speed, gS.session_chars, duration_sec)
    elseif gS.has_previous_session then
        -- Show previous session statistics
        local prefix = gS.show_current_speed and "Current Speed" or "Last Speed"
        return string.format("%s: %d chars/min\nCharacters: %d\nTime: %.1f sec", 
                           prefix, gS.last_session_speed, gS.last_session_chars, gS.last_session_time)
    else
        -- Show help message
        return "Speed Statistics\nType |tjd for detailed stats\nType |tjk to end session manually"
    end
end

-- Format character count statistics summary
function M.format_char_stats_summary()
    M.update_date_stats()
    
    -- Calculate average speeds for each period
    local daily_avg = M.calculate_avg_speed("daily")
    local monthly_avg = M.calculate_avg_speed("monthly")
    local yearly_avg = M.calculate_avg_speed("yearly")
    local total_avg = M.calculate_avg_speed("total")
    
    return string.format("Today: %d chars (Avg: %d chars/min)\nThis Month: %d chars (Avg: %d chars/min)\nThis Year: %d chars (Avg: %d chars/min)\nTotal: %d chars (Avg: %d chars/min)",
                       gS.char_stats.daily, daily_avg,
                       gS.char_stats.monthly, monthly_avg,
                       gS.char_stats.yearly, yearly_avg,
                       gS.char_stats.total, total_avg)
end

-- Main translator function
function M.func(input, seg, env)
    if input == "|tj" then 
        -- Show speed statistics
        local summary = M.format_speed_summary()
        yield(Candidate("punct", seg.start, seg._end, summary, "Speed Stats"))
    elseif input == "|tjd" then
        -- Show detailed statistics
        local summary = M.format_char_stats_summary()
        yield(Candidate("punct", seg.start, seg._end, summary, "Detailed Stats"))
    elseif input == "|tjk" then
        -- End session manually
        if M.end_session_manually() then
            yield(Candidate("punct", seg.start, seg._end, "Session ended manually", "Status"))
        else
            yield(Candidate("punct", seg.start, seg._end, "No active session", "Status"))
        end
    end
end

-- Initialize the plugin
function M.init(env)
    if M.init_flag then return end
    
    -- Load saved statistics
    M.load_stats()
    
    -- Reset session state
    gS.session_start = 0
    gS.last_commit_time = 0
    gS.session_chars = 0
    gS.session_active = false
    gS.show_current_speed = false
    
    -- Ensure date statistics are up to date
    M.update_date_stats()
    
    -- Commit callback handler
    local function commit_callback(ctx)
        local input_text = ctx.input
        -- Clear input if it's a command
        if input_text and input_text:match("^|tj[dk]?$") then
            ctx:clear()
            return
        end
        
        -- Update statistics on text commit
        local commit_text = ctx:get_commit_text()
        if commit_text then
            local input_length = M.get_commit_length(commit_text)
            if input_length > 0 then
                M.update_stats(input_length)
            end
        end
    end
    
    -- Connect event handlers
    env.engine.context.commit_notifier:connect(commit_callback)
    env.engine.context.unhandled_key_notifier:connect(key_event_callback)
    
    M.init_flag = true
    debug_print("Speed statistics plugin initialized")
end

-- Cleanup function
function M.fini(env)
    -- Save all data before cleanup
    M.save_stats(true)
    debug_print("Speed statistics plugin cleanup completed")
end

return M