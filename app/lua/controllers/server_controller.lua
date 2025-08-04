-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Modern Server Controller using new router and middleware system

local cjson = require "cjson"
local command = require "core.command"

local _M = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

-- 配置文件目录
local SERVER_CONFIG_DIR = "/app/configs"
local SERVER_CONFIG_PREFIX = "server_"
local SERVER_CONFIG_SUFFIX = ".conf"
local DISABLED_SUFFIX = ".disabled"
local BACKUP_SUFFIX = ".backup"

-- ============================================================================
-- 文件操作工具函数
-- ============================================================================

-- 工具函数：检查文件是否存在
local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- 工具函数：读取文件内容
local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil, "File not found: " .. path
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- 工具函数：写入文件内容
local function write_file(path, content)
    -- 参数类型检查
    if type(path) ~= "string" then
        return false, "Path must be a string, got " .. type(path) .. " with value: " .. tostring(path)
    end
    if type(content) ~= "string" then
        return false, "Content must be a string, got " .. type(content) .. " with value: " .. tostring(content)
    end
    
    local file = io.open(path, "w")
    if not file then
        return false, "Cannot write to file: " .. path
    end
    file:write(content)
    file:close()
    return true
end

-- 工具函数：移动文件
local function move_file(from_path, to_path)
    return os.rename(from_path, to_path)
end

-- 工具函数：删除文件
local function delete_file(path)
    if file_exists(path) then
        return os.remove(path)
    end
    return true
end

-- 工具函数：获取文件修改时间
local function get_file_mtime(path)
    local cmd = "stat -c %Y " .. path .. " 2>/dev/null || echo 0"
    local handle = io.popen(cmd)
    if not handle then
        return 0
    end
    local result = handle:read("*a")
    handle:close()
    return tonumber(result) or 0
end

-- 工具函数：创建临时测试文件
local function create_temp_test_file(paths, content)
    local temp_path = paths.enabled .. ".testing"
    local success, err = write_file(temp_path, content)
    if not success then
        return nil, err
    end
    return temp_path
end

-- 工具函数：清理临时文件
local function cleanup_temp_file(temp_path)
    if temp_path and file_exists(temp_path) then
        delete_file(temp_path)
    end
end

-- ============================================================================
-- 服务器配置文件管理函数
-- ============================================================================

-- 工具函数：生成不同状态的文件路径
local function get_server_paths(server_name)
    local base_path = SERVER_CONFIG_DIR .. "/" .. SERVER_CONFIG_PREFIX .. server_name
    return {
        enabled = base_path .. SERVER_CONFIG_SUFFIX,
        disabled = base_path .. SERVER_CONFIG_SUFFIX .. DISABLED_SUFFIX,
        backup = base_path .. SERVER_CONFIG_SUFFIX .. BACKUP_SUFFIX
    }
end

-- 工具函数：查找服务器配置文件（任何状态）
local function find_server_file(server_name)
    local paths = get_server_paths(server_name)
    
    if file_exists(paths.enabled) then
        return paths.enabled, "enabled"
    elseif file_exists(paths.disabled) then
        return paths.disabled, "disabled"
    elseif file_exists(paths.backup) then
        return paths.backup, "backup"
    end
    
    return nil, nil
end

-- 工具函数：解析服务器配置文件状态
local function parse_server_file(filename)
    local base_name = filename:match("^" .. SERVER_CONFIG_PREFIX .. "(.+)$")
    if not base_name then
        return nil
    end
    
    local server_name, status, actual_suffix
    
    if base_name:match(SERVER_CONFIG_SUFFIX .. "$") then
        -- 正常启用的文件: server_name.conf
        server_name = base_name:match("^(.+)" .. SERVER_CONFIG_SUFFIX .. "$")
        status = "enabled"
        actual_suffix = SERVER_CONFIG_SUFFIX
    elseif base_name:match(SERVER_CONFIG_SUFFIX .. DISABLED_SUFFIX .. "$") then
        -- 禁用的文件: server_name.conf.disabled
        server_name = base_name:match("^(.+)" .. SERVER_CONFIG_SUFFIX .. DISABLED_SUFFIX .. "$")
        status = "disabled"
        actual_suffix = SERVER_CONFIG_SUFFIX .. DISABLED_SUFFIX
    elseif base_name:match(SERVER_CONFIG_SUFFIX .. BACKUP_SUFFIX .. "$") then
        -- 备份文件: server_name.conf.backup
        server_name = base_name:match("^(.+)" .. SERVER_CONFIG_SUFFIX .. BACKUP_SUFFIX .. "$")
        status = "backup"
        actual_suffix = SERVER_CONFIG_SUFFIX .. BACKUP_SUFFIX
    else
        return nil
    end
    
    return {
        name = server_name,
        status = status,
        filename = filename,
        actual_suffix = actual_suffix
    }
end

-- 工具函数：获取所有 server 配置文件
local function get_server_configs()
    local configs = {}
    local cmd = "ls " .. SERVER_CONFIG_DIR .. "/" .. SERVER_CONFIG_PREFIX .. "* 2>/dev/null || true"
    local handle = io.popen(cmd)
    if not handle then
        return configs
    end
    
    local output = handle:read("*a")
    if handle then
        handle:close()
    end
    
    if not output then
        return configs
    end
    
    for filepath in output:gmatch("[^\r\n]+") do
        local filename = filepath:match("([^/]+)$")
        local server_info = parse_server_file(filename)
        
        if server_info then
            local content = read_file(filepath)
            if content then
                table.insert(configs, {
                    name = server_info.name,
                    status = server_info.status,
                    filename = server_info.filename,
                    filepath = filepath,
                    content = content,
                    size = #content,
                    updated_at = get_file_mtime(filepath)
                })
            end
        end
    end
    
    return configs
end

-- ============================================================================
-- Nginx 操作函数
-- ============================================================================

-- 工具函数：从配置内容中提取 server_name
local function extract_server_names(content)
    if not content or type(content) ~= "string" then
        return "N/A"
    end
    
    local server_names = {}
    -- 匹配 server_name 指令，并捕获后面的所有值，直到分号
    -- 考虑到多行和注释的情况
    local stripped_content = content:gsub("#[^\r\n]*", "") -- 移除注释
    for line in stripped_content:gmatch("[^\r\n]+") do
        local match = line:match("server_name%s+([^;]+)")
        if match then
            -- 移除可能的前后空格
            local names_str = match:gsub("^%s*", ""):gsub("%s*$", "")
            -- 按空格分割捕获到的字符串
            for name in names_str:gmatch("%S+") do
                table.insert(server_names, name)
            end
            -- 找到第一个 server_name 就停止
            if #server_names > 0 then
                break
            end
        end
    end

    if #server_names > 0 then
        return table.concat(server_names, " ")
    else
        return "N/A"
    end
end

-- 工具函数：测试 nginx 配置
local function test_nginx_config()
    return command.nginx_test()
end

-- 工具函数：重新加载 nginx
local function reload_nginx()
    return command.nginx_reload()
end

-- ============================================================================
-- 状态和响应工具函数
-- ============================================================================

-- 工具函数：获取状态描述
local function get_status_description(status)
    local descriptions = {
        enabled = "生效中",
        disabled = "已禁用", 
        backup = "待测试状态"
    }
    return descriptions[status] or "未知状态"
end

-- 工具函数：获取可用操作
local function get_available_actions(status)
    local actions = {
        enabled = {"disable"},        -- 生效中的配置可以禁用
        disabled = {"enable"},        -- 禁用状态可以启用或更新
        backup = {"test"}             -- 待测试状态只能测试
    }
    return actions[status] or {}
end

-- 工具函数：构建响应数据
local function build_response_data(server_name, status, size, context)
    return {
        name = server_name,
        status = status,
        enabled = status == "enabled",
        description = get_status_description(status),
        size = size,
        updated_at = ngx.time(),
        updated_by = context.user and context.user.id or "system",
        next_actions = get_available_actions(status)
    }
end


-- ============================================================================
-- 主要 API 端点函数
-- ============================================================================

-- 辅助函数：统计指定状态的服务器数量
local function count_by_status(servers, status)
    local count = 0
    for _, server in ipairs(servers) do
        if server.status == status then
            count = count + 1
        end
    end
    return count
end

-- GET /servers - 获取所有server配置
function _M.list(context)
    local configs = get_server_configs()
    local servers = {}
    
    for _, config in ipairs(configs) do
        local response_data = build_response_data(config.name, config.status, config.size, context)
        response_data.updated_at = config.updated_at
        response_data.filename = config.filename
        response_data.server_name = extract_server_names(config.content)
        table.insert(servers, response_data)
    end
    
    return context.response.success({
        items = servers,
        total = #servers,
        status_summary = {
            total = #servers,
            enabled = count_by_status(servers, "enabled"),
            disabled = count_by_status(servers, "disabled"),
            backup = count_by_status(servers, "backup")
        }
    })
end

-- GET /servers/{name} - 获取单个server配置
function _M.get(context)
    local server_name = context.params.name
    
    if not server_name then
        return context.response.error("Server name is required", 400)
    end
    
    local filepath, status = find_server_file(server_name)
    if not filepath then
        return context.response.error("Server config not found: " .. server_name, 404)
    end
    
    local content, err = read_file(filepath)
    if not content then
        return context.response.error("Failed to read server config: " .. err, 500)
    end
    
    -- 返回结构化对象，将内容作为对象的一部分
    return context.response.success({
        name = server_name,
        status = status,
        description = get_status_description(status),
        enabled = status == "enabled",
        next_actions = get_available_actions(status),
        filepath = filepath,
        size = #content,
        content = content,
        server_name = extract_server_names(content)
    }, "Server config retrieved successfully", 200)
end

-- POST /servers - 创建新的server配置
function _M.create(context)
    local server_name = context.params.name
    
    if not server_name then
        return context.response.error("Server name is required", 400)
    end
    
    -- 检查是否已存在任何状态的配置
    local existing_path, existing_status = find_server_file(server_name)
    if existing_path then
        return context.response.error("Server config already exists with status: " .. existing_status, 409)
    end
    
    -- 获取请求体内容（纯文本）
    local body = context.body
    if not body then
        return context.response.error("Request body is required", 400)
    end
    
    -- 确保 body 是字符串类型
    if type(body) ~= "string" then
        if type(body) == "table" then
            body = cjson.encode(body)
        else
            body = tostring(body)
        end
    end
    
    -- 直接写入 backup 文件
    local paths = get_server_paths(server_name)
    local success, err = write_file(paths.backup, body)
    if not success then
        return context.response.error("Failed to create backup file: " .. err, 500)
    end
    
    -- 构建返回数据
    local response_data = build_response_data(server_name, "backup", #body, context)
    response_data.created_at = ngx.time()
        
    return context.response.success(response_data, "Server config created in backup state. Use action=test to validate.", 201, {
        message = "Configuration saved as backup. Use POST /servers/" .. server_name .. "/action?action=test to validate and move to disabled state."
    })
end

-- PUT /servers/{name} - 更新server配置
function _M.update(context)
    local server_name = context.params.name
    
    if not server_name then
        return context.response.error("Server name is required", 400)
    end
    
    -- 检查配置是否存在
    local existing_path, existing_status = find_server_file(server_name)
    if not existing_path then
        return context.response.error("Server config not found: " .. server_name, 404)
    end
    
    -- 只允许更新disabled和backup状态的服务器配置
    if existing_status ~= "disabled" and existing_status ~= "backup" then
        return context.response.error("Cannot update server config. Server must be in disabled or backup state before updating. Current status: " .. existing_status, 403, {
            current_status = existing_status,
            allowed_status = {"disabled", "backup"},
            message = "Please disable the server first before updating configuration"
        })
    end
    
    -- 获取请求体内容
    local body = context.body
    if not body then
        return context.response.error("Request body is required", 400)
    end
    
    -- 确保 body 是字符串类型
    if type(body) ~= "string" then
        if type(body) == "table" then
            body = cjson.encode(body)
        else
            body = tostring(body)
        end
    end
    
    -- 获取所有可能的路径
    local paths = get_server_paths(server_name)
    
    -- 根据当前状态执行不同的操作
    if existing_status == "disabled" then
        -- 如果是disabled状态，删除现有文件并写入backup
        delete_file(paths.disabled)
    elseif existing_status == "backup" then
        -- 如果是backup状态，删除现有的backup文件
        delete_file(paths.backup)
    end
    
    -- 写入新的backup文件
    local success, err = write_file(paths.backup, body)
    if not success then
        return context.response.error("Failed to create backup file: " .. err, 500)
    end
    
    -- 构建返回数据
    local response_data = build_response_data(server_name, "backup", #body, context)
    response_data.previous_status = existing_status
        
    return context.response.success(response_data, "Server config updated and saved as backup. Use action=test to validate.", 200, {
        message = "Configuration updated and saved as backup. Use POST /servers/" .. server_name .. "/action?action=test to validate and move to disabled state."
    })
end

-- DELETE /servers/{name} - 删除server配置
function _M.delete(context)
    local server_name = context.params.name
    
    if not server_name then
        return context.response.error("Server name is required", 400)
    end
    
    -- 检查配置是否存在
    local existing_path, existing_status = find_server_file(server_name)
    if not existing_path then
        return context.response.error("Server config not found: " .. server_name, 404)
    end
    
    -- 删除所有状态文件
    local paths = get_server_paths(server_name)
    local backup_content = nil
    
    -- 先保存原始内容用于可能的恢复
    if file_exists(existing_path) then
        backup_content = read_file(existing_path)
    end
    
    -- 删除所有可能的状态文件
    delete_file(paths.enabled)
    delete_file(paths.disabled)
    delete_file(paths.backup)
    
    -- 测试 nginx 配置
    local test_ok, test_result = test_nginx_config()
    ngx.log(ngx.INFO, "test_result: " .. cjson.encode(test_result))
    if not test_ok then
        -- 测试失败，恢复原配置
        if backup_content then
            write_file(existing_path, backup_content)
        end
        
        return context.response.error("Nginx configuration test failed after deletion; original config restored", 500, test_result)
    end
    
    -- 重新加载 nginx
    local reload_ok, reload_result = reload_nginx()
    if not reload_ok then
        if ngx and ngx.log then 
            ngx.log(ngx.ERR, "nginx reload failed: " .. cjson.encode(reload_result)) 
        end
    end
    
    -- 构建返回数据
    local response_data = { 
        deleted_server = server_name,
        deleted_file = existing_path,
        original_status = existing_status
    }
    
    local response_detail = {
        nginx_test_output = test_result,
        reload_result = reload_result
    }
    if not reload_ok then
        response_detail.reload_warning = reload_result.stderr or reload_result.reason
    end
    
    return context.response.success(response_data, "Server config deleted successfully", 200, response_detail)
end

-- ============================================================================
-- 服务器操作处理函数
-- ============================================================================

-- 处理 test 操作 - 只能操作 backup 文件
local function handle_test_action(server_name, paths, context)
    -- 检查是否存在 backup 文件
    if not file_exists(paths.backup) then
        return context.response.error("No backup file found for server: " .. server_name .. ". Only backup files can be tested.", 404)
    end
    
    -- 读取 backup 文件内容
    local content = read_file(paths.backup)
    if not content then
        return context.response.error("Failed to read backup file", 500)
    end
    
    -- 检查是否已存在 enabled 文件，如果存在则不能进行测试
    if file_exists(paths.enabled) then
        return context.response.error("Cannot test backup file while an enabled configuration exists for server: " .. server_name .. ". Please disable the server first.", 409)
    end
    
    -- 创建临时测试文件（使用 .conf 后缀以便 nginx 能够加载）
    local temp_path = paths.enabled
    local success, err = write_file(temp_path, content)
    if not success then
        return context.response.error("Failed to create test file: " .. err, 500)
    end
    
    -- 测试 nginx 配置
    local test_ok, test_result = test_nginx_config()
    
    -- 清理临时文件
    delete_file(temp_path)
    
    if test_ok then
        -- 测试成功，直接将backup文件移动到disabled状态
        local move_success = move_file(paths.backup, paths.disabled)
        if not move_success then
            return context.response.error("Failed to rename file from backup to disabled state", 500)
        end
        
        local response_data = {
            name = server_name,
            action = "test",
            status = "success",
            previous_state = "backup",
            current_state = "disabled",
            message = "Configuration test passed, moved to disabled state"
        }
        
        return context.response.success(response_data, "Server configuration test passed", 200, {
            test_output = test_result
        })
    else
        -- 测试失败，保持backup状态不变
        local response_data = {
            name = server_name,
            action = "test",
            status = "failed",
            current_state = "backup",
            message = "Configuration test failed, still in backup state"
        }
        
        return context.response.error("Server configuration test failed", 500, {
            test_output = test_result,
            server_data = response_data
        })
    end
end

-- 处理 enable 操作 - 只能操作 disabled 文件
local function handle_enable_action(server_name, paths, context)
    -- 检查是否存在 disabled 文件
    if not file_exists(paths.disabled) then
        return context.response.error("No disabled file found for server: " .. server_name .. ". Only disabled files can be enabled.", 404)
    end
    
    -- 读取 disabled 文件内容
    local content = read_file(paths.disabled)
    if not content then
        return context.response.error("Failed to read disabled file", 500)
    end
    
    -- 简化操作：直接将文件改名为enabled状态
    local success = move_file(paths.disabled, paths.enabled)
    if not success then
        return context.response.error("Failed to rename file from disabled to enabled state", 500)
    end
    
    -- 测试 nginx 配置
    local test_ok, test_result = test_nginx_config()
    if not test_ok then
        -- 测试失败，回滚到 disabled 状态
        move_file(paths.enabled, paths.disabled)
        return context.response.error("Nginx configuration test failed after enabling; reverted to disabled state", 500, {
            test_output = test_result
        })
    end
    
    -- 重新加载 nginx
    local reload_ok, reload_result = reload_nginx()
    
    local response_data = {
        name = server_name,
        action = "enable",
        status = "success",
        previous_state = "disabled",
        current_state = "enabled",
        message = "Server configuration enabled successfully"
    }
    
    local response_detail = {
        test_output = test_result,
        reload_result = reload_result
    }
    
    if not reload_ok then
        response_detail.reload_warning = reload_result.stderr or reload_result.reason
    end
    
    return context.response.success(response_data, "Server configuration enabled successfully", 200, response_detail)
end

-- 处理 disable 操作 - 只能操作 conf 文件, 改名后直接 reload
local function handle_disable_action(server_name, paths, context)
    -- 检查是否存在 enabled 文件
    if not file_exists(paths.enabled) then
        return context.response.error("No enabled file found for server: " .. server_name .. ". Only enabled files can be disabled.", 404)
    end
    
    -- 读取 enabled 文件内容
    local content = read_file(paths.enabled)
    if not content then
        return context.response.error("Failed to read enabled file", 500)
    end
    
    -- 简化操作：直接将文件改名为disabled状态
    local success = move_file(paths.enabled, paths.disabled)
    if not success then
        return context.response.error("Failed to rename file from enabled to disabled state", 500)
    end
    
    -- 重新加载 nginx
    local reload_ok, reload_result = reload_nginx()
    
    local response_data = {
        name = server_name,
        action = "disable",
        status = "success",
        previous_state = "enabled",
        current_state = "disabled",
        message = "Server configuration disabled successfully"
    }
    
    local response_detail = {
        reload_result = reload_result
    }
    
    if not reload_ok then
        response_detail.reload_warning = reload_result.stderr or reload_result.reason
    end
    
    return context.response.success(response_data, "Server configuration disabled successfully", 200, response_detail)
end

-- POST /servers/{name}/action - 执行服务器操作 (test/enable/disable)
function _M.action(context)
    local server_name = context.params.name
    local action = context.query.action
    
    if not server_name then
        return context.response.error("Server name is required", 400)
    end
    
    if not action then
        return context.response.error("Action parameter is required (action=test|enable|disable)", 400)
    end
    
    -- 验证操作类型
    if action ~= "test" and action ~= "enable" and action ~= "disable" then
        return context.response.error("Invalid action. Must be: test, enable, or disable", 400)
    end
    
    local paths = get_server_paths(server_name)
    
    if action == "test" then
        return handle_test_action(server_name, paths, context)
    elseif action == "enable" then
        return handle_enable_action(server_name, paths, context)
    elseif action == "disable" then
        return handle_disable_action(server_name, paths, context)
    end
  end
  
  -- Get path settings
function _M.get_path_settings(context)
    local config = require "core.config"
    local admin_config = config.get_config("admin") or {}
    local paths = admin_config.paths or {
        logs_dir = "/var/log/nginx/",
        reports_dir = "/app/web/reports/"
    }
    
    return context.response.success(paths)
end

-- Update path settings
function _M.update_path_settings(context)
    local config = require "core.config"
    local paths = context.body or {}
    
    -- Validate paths
    if not paths.logs_dir or not paths.reports_dir then
        return context.response.error("Missing required path settings", 400)
    end
    
    -- Make sure paths end with a slash
    if not paths.logs_dir:match("/$") then
        paths.logs_dir = paths.logs_dir .. "/"
    end
    if not paths.reports_dir:match("/$") then
        paths.reports_dir = paths.reports_dir .. "/"
    end
    
    -- Get current admin config
    local admin_config = config.get_config("admin") or {}
    
    -- Update paths in admin config
    admin_config.paths = paths
    
    -- Save the configuration
    local ok, err = config.set_config("admin", admin_config)
    if not ok then
        return context.response.error("Failed to update path settings: " .. (err or "unknown error"), 500)
    end
    
    -- Create the reports directory if it doesn't exist
    os.execute("mkdir -p " .. paths.reports_dir)
    os.execute("chmod -R 777 " .. paths.reports_dir)
    
    -- Reload config in memory
    config.reload_module_config("admin")
    
    return context.response.success(paths)
end
  
  return _M 