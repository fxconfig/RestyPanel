-- app/lua/core/logs.lua
-- Service for log analysis functionality using lua-resty-shell

local cjson = require "cjson"
local util = require "core.util"
local shell = require "resty.shell"
local io = require "io"
local os = require "os"
local ngx = ngx
local string = string
local config = require "core.config"

local _M = {}

-- 常量定义及安全获取配置
local function safe_get_path(path_key, default_value)
    local configs = config.get_configs()
    if configs and configs.admin then
        if configs.admin.paths and configs.admin.paths[path_key] then
            return configs.admin.paths[path_key]
        end
        
        -- 如果admin中没有paths配置项，尝试创建默认配置
        if not configs.admin.paths then
            configs.admin.paths = {
                logs_dir = "/var/log/nginx/",
                reports_dir = "/app/web/reports/"
            }
            
            -- 尝试保存更新的配置
            pcall(function()
                config.save_module_config("admin", configs.admin)
                ngx.log(ngx.NOTICE, "Created default paths in admin config")
            end)
            
            return configs.admin.paths[path_key]
        end
    end
    
    return default_value
end

local LOGS_DIR = safe_get_path("logs_dir", "/var/log/nginx/")
local REPORTS_DIR = safe_get_path("reports_dir", "/app/web/reports/")

-- Base directory for logs - get from config
-- local LOGS_DIR = config.get_configs().admin.paths.logs_dir or "/var/log/nginx/"
-- Directory for storing GoAccess reports - get from config
-- local REPORTS_DIR = config.get_configs().admin.paths.reports_dir or "/app/web/repor
-- Make sure the reports directory exists with proper permissions
os.execute("mkdir -p " .. REPORTS_DIR)
os.execute("chmod -R 777 " .. REPORTS_DIR)

-- Sanitize filename to prevent directory traversal
local function sanitize_filename(filename)
    if not filename then return nil end
    filename = string.match(filename, "[^/\\]+$")
    if not filename or filename:find("%.%.") then
        return nil
    end
    return filename
end

-- Get list of log files using a more compatible find command
function _M.get_log_files()
    local command = "find " .. LOGS_DIR .. " -maxdepth 1 -type f -name '*.log' -print0 | xargs -0 stat -c '%n\\t%s\\t%Y'"
    local ok, stdout, stderr, reason, status = shell.run(command, nil, 2000)

    if not ok or (reason == "exit" and status ~= 0) then
        local err_msg = "Failed to list log files. "
        if stderr and stderr ~= "" then
            err_msg = err_msg .. "Error: " .. stderr
        else
            err_msg = err_msg .. "Reason: " .. (reason or "unknown") .. ", Status: " .. (status or "unknown")
        end
        return nil, err_msg .. ". Make sure Nginx has permission to access " .. LOGS_DIR
    end

    local files = {}
    if stdout and stdout ~= "" then
        for line in string.gmatch(stdout, "[^\n]+") do
            if line ~= "" then
                local parts = {}
                local current_pos = 1
                for i = 1, 2 do
                    -- The stdout appears to contain a literal backslash and 't', not a tab character.
                    -- We search for the two-character string "\\t".
                    local tab_pos = string.find(line, "\\t", current_pos, true)
                    if not tab_pos then
                        break
                    end
                    table.insert(parts, string.sub(line, current_pos, tab_pos - 1))
                    -- Move the cursor past the two-character delimiter "\\t"
                    current_pos = tab_pos + 2
                end
                table.insert(parts, string.sub(line, current_pos))

                if #parts == 3 then
                    local full_path = parts[1]
                    local size = tonumber(parts[2])
                    local modified = tonumber(parts[3])
                    local filename = string.match(full_path, "[^/]+$")

                    if filename and size and modified then
                        table.insert(files, {
                            name = filename,
                            size = size,
                            modified = modified,
                            path = full_path
                        })
                    end
                end
            end
        end
    end

    table.sort(files, function(a, b) return a.modified > b.modified end)
    return files, nil
end

-- Read log file content with pagination and filtering
function _M.get_log_content(filename, page, page_size, filter)
    filename = sanitize_filename(filename)
    if not filename then return nil, 0, "Invalid filename" end

    local filepath = LOGS_DIR .. filename
    local file, err = io.open(filepath, "r")
    if not file then return nil, 0, "Failed to open file: " .. tostring(err) end

    -- Read all lines into a table first
    local all_lines = {}
    for line in file:lines() do
        table.insert(all_lines, line)
    end
    file:close()

    -- Reverse the table to have the newest logs first
    local reversed_lines = {}
    for i = #all_lines, 1, -1 do
        table.insert(reversed_lines, all_lines[i])
    end

    local lines = {}
    local matched_lines_count = 0
    local start_line = (page - 1) * page_size + 1
    local end_line = page * page_size

    for _, line in ipairs(reversed_lines) do
        if filter == "" or string.find(line, filter, 1, true) then
            matched_lines_count = matched_lines_count + 1
            if matched_lines_count >= start_line and matched_lines_count <= end_line then
                table.insert(lines, line)
            end
        end
    end
    
    return lines, matched_lines_count, nil
end

-- Generate a unique ID for a report
local function generate_report_id()
    return os.time() .. "_" .. math.random(1000, 9999)
end

-- Generate a report filename with log filename as prefix
local function generate_report_filename(log_filename, is_realtime)
    -- Remove .log extension if present
    local prefix = log_filename:gsub("%.log$", "")
    -- Replace any special characters with underscore
    prefix = prefix:gsub("[^%w_-]", "_")
    
    if is_realtime  then
        return prefix .. "_realtime_" .. ".html"
    else
        local id = generate_report_id()
        return prefix .. "_report_" .. id .. ".html"
    end    
end

local function execute_shell_command(cmd_parts)
    -- Remove "sudo" from the command parts if it exists
    if cmd_parts[1] == "sudo" then
        table.remove(cmd_parts, 1)
    end
    local ok, stdout, stderr, reason, status = shell.run(cmd_parts, nil, 30000) -- 30s timeout
    if not ok or (reason == "exit" and status ~= 0) then
        local err_msg = "Command failed. "
        if stderr and stderr ~= "" then
            err_msg = err_msg .. "Error: " .. stderr
        else
            err_msg = err_msg .. "Reason: " .. (reason or "unknown") .. ", Status: " .. (status or "unknown")
        end
        return nil, err_msg
    end
    return stdout, nil
end

-- Run GoAccess to analyze a log file
function _M.analyze_log(filename, options)
    filename = sanitize_filename(filename)
    if not filename then return nil, "Invalid filename" end

    local filepath = LOGS_DIR .. filename
    local report_filename = generate_report_filename(filename, options and options.real_time)
    local report_path = REPORTS_DIR .. report_filename

    -- Define the command with full log format specification
    local cmd = {
        "goaccess", filepath,
        "-o", report_path,
        "--log-format='%h - %^ [%d:%t %^] \"%r\" %s %b \"%R\" \"%u\" \"%^\"'",
        "--date-format=%d/%b/%Y",
        "--time-format=%H:%M:%S"
    }
    
    -- 如果请求实时分析，添加相关参数
    if options and options.real_time then
        -- 添加实时分析参数
        table.insert(cmd, "--real-time-html")
        
        -- 如果指定了WebSocket端口，添加端口参数
        if options.ws_port then
            table.insert(cmd, "--port=" .. options.ws_port)
        end
        
        -- 如果指定了WebSocket URL，添加URL参数
        if options.ws_url then
            table.insert(cmd, "--ws-url=" .. options.ws_url)
        end
        
        -- 在后台运行
        table.insert(cmd, "&")
    end
    
    local _, err = execute_shell_command(cmd)
    if err then
        return nil, "GoAccess analysis failed. " .. err
    end

    return "/reports/" .. report_filename, nil
end

-- 获取所有报告列表
function _M.get_reports()
    local reports = {}
    
    -- 检查报告目录是否存在
    local ok, err = util.check_dir_exists(REPORTS_DIR)
    if not ok then
        ngx.log(ngx.ERR, "Failed to check reports directory: " .. (err or "unknown error"))
        return {}
    end
    
    -- 列出所有报告文件
    local files = util.list_files(REPORTS_DIR)
    
    -- 过滤HTML报告文件
    for _, file in ipairs(files) do
        if string.match(file, "%.html$") then
            local id = file:match("^(.+)%.html$")
            -- 确保路径不包含多余斜杠
            local path_separator = string.sub(REPORTS_DIR, -1) == "/" and "" or "/"
            local full_path = REPORTS_DIR .. path_separator .. file
            local stat = util.file_stat(full_path)
                        
            table.insert(reports, {
                id = id,
                name = file,
                path = full_path,
                url = "/reports/" .. file,
                size = stat and stat.size or 0,
                mtime = stat and stat.mtime or 0
            })
        end
    end
    
    -- 按修改时间排序，最新的在前
    table.sort(reports, function(a, b) return a.mtime > b.mtime end)
    
    return reports
end


-- Delete a specific report
function _M.delete_report(report_name)
    report_name = sanitize_filename(report_name)
    if not report_name then return false, "Invalid report name" end
    
    -- Only add .html extension if not already present
    if not string.match(report_name, "%.html$") then
        report_name = report_name .. ".html"
    end
    
    local report_path = REPORTS_DIR .. report_name
    
    -- Check if file exists
    local file, err = io.open(report_path, "r")
    if not file then
        return false, "Report not found: " .. tostring(err)
    end
    file:close()
    
    -- Delete the file
    local success, err = os.remove(report_path)
    if not success then
        return false, "Failed to delete report: " .. tostring(err)
    end
    
    return true, nil
end

-- Delete all reports
function _M.delete_all_reports()
    local command = "rm -f " .. REPORTS_DIR .. "*.html"
    local ok, _, stderr, reason, status = shell.run(command, nil, 5000)
    
    if not ok or (reason == "exit" and status ~= 0) then
        local err_msg = "Failed to delete all reports. "
        if stderr and stderr ~= "" then
            err_msg = err_msg .. "Error: " .. stderr
        else
            err_msg = err_msg .. "Reason: " .. (reason or "unknown") .. ", Status: " .. (status or "unknown")
        end
        return false, err_msg
    end
    
    return true, nil
end

return _M 