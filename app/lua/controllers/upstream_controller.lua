-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Modern Upstream Controller using new router and middleware system

local cjson = require "cjson"
local command = require "core.command"

local _M = {}

-- 配置文件路径
local CONFIG_FILE = "/app/configs/upstream_config.json"
local UPSTREAM_CONF_FILE = "/app/configs/upstream.conf"

-- 工具函数：检查upstream是否有启用的服务器
local function has_enabled_servers(upstream_config)
    if not upstream_config.servers or #upstream_config.servers == 0 then
        return false
    end
    
    for _, server in ipairs(upstream_config.servers) do
        local enabled = true
        if type(server) == "table" and server.enable == false then
            enabled = false
        end
        if enabled then
            return true
        end
    end
    
    return false
end

-- 工具函数：处理HTTP请求格式，确保换行符是\r\n
local function normalize_http_req(http_req)
    if not http_req or type(http_req) ~= "string" then
        return http_req
    end
    
    -- 将单独的\n替换为\r\n (排除已经是\r\n的情况)
    return http_req:gsub("\r?\n", "\r\n")
end

-- 工具函数：处理upstream配置中的health_check
local function process_health_check(config)
    if not config or not config.health_check then
        return config
    end
    
    if config.health_check.http_req then
        config.health_check.http_req = normalize_http_req(config.health_check.http_req)
    end
    
    return config
end

-- 工具函数：读取配置
local function load_config()
    local file = io.open(CONFIG_FILE, "r")
    if not file then
        return nil, "Configuration file not found"
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, config = pcall(cjson.decode, content)
    if not success then
        return nil, "Failed to parse configuration"
    end
    
    return config, nil
end

-- 工具函数：保存配置
local function save_config(config)
    local file = io.open(CONFIG_FILE, "w")
    if not file then
        return false, "Cannot write configuration file"
    end
    
    local config_json = cjson.encode(config)
    file:write(config_json)
    file:close()
    
    return true, nil
end

-- 工具函数：生成并写入 upstream.conf
local function write_upstream_conf(config)
    -- helper to check if a Lua table is an array (sequential numeric keys)
    local function is_array(tbl)
        if type(tbl) ~= "table" then return false end
        local i = 0
        for k, _ in pairs(tbl) do
            i = i + 1
            if k ~= i then
                return false
            end
        end
        return true
    end

    -- 若无 upstream 配置，直接清空文件并返回
    local file, err = io.open(UPSTREAM_CONF_FILE, "w")
    if not file then
        return false, "Cannot write upstream conf: " .. (err or "unknown error")
    end

    if not config or not config.upstreams then
        file:close()
        return true, nil
    end

    for name, upstream_cfg in pairs(config.upstreams) do
        -- 1. 跳过未启用的 upstream
        if upstream_cfg.enable == false then
            goto continue_upstream
        end

        -- 2. 统计启用的 server
        local server_lines = {}
        if upstream_cfg.servers then
            for _, s in ipairs(upstream_cfg.servers) do
                local enabled = true
                local address
                local weight = ""

                if type(s) == "table" then
                    if s.enable == false then
                        enabled = false
                    end

                    if s.server then
                        address = s.server
                    elseif s.host then
                        if s.port then
                            address = tostring(s.host) .. ":" .. tostring(s.port)
                        else
                            address = s.host
                        end
                    else
                        address = s.address or s[1]
                    end

                    if s.weight then
                        weight = " weight=" .. s.weight
                    end
                else
                    address = tostring(s)
                end

                if enabled and address then
                    table.insert(server_lines, "    server " .. address .. weight .. ";\n")
                end
            end
        end

        -- 3. 没有启用的 server，跳过整个 upstream
        if #server_lines == 0 then
            goto continue_upstream
        end

        -- 4. 只有满足条件才写入 upstream 块
        file:write("upstream ", name, " {\n")
        -- 写 server_lines
        for _, line in ipairs(server_lines) do
            file:write(line)
        end

        -- 写其它官方 upstream 指令
        local skip_keys = {
            servers = true,
            balance_method = true,
            enable = true,
            created_at = true,
            created_by = true,
            updated_at = true,
            updated_by = true,
            name = true,
            health_check = true -- 非官方，忽略
        }

        for k, v in pairs(upstream_cfg) do
            if not skip_keys[k] then
                if type(v) == "boolean" then
                    if v then
                        file:write("    ", k, ";\n")
                    end
                elseif type(v) == "string" or type(v) == "number" then
                    file:write("    ", k, " ", v, ";\n")
                elseif type(v) == "table" then
                    if k == "keepalive" then
                        if v.connections then
                            file:write("    keepalive ", v.connections, ";\n")
                        end
                        if v.timeout then
                            file:write("    keepalive_timeout ", v.timeout, ";\n")
                        end
                        if v.requests then
                            file:write("    keepalive_requests ", v.requests, ";\n")
                        end
                    elseif is_array(v) then
                        local parts = {}
                        for _, itm in ipairs(v) do
                            table.insert(parts, tostring(itm))
                        end
                        file:write("    ", k, " ", table.concat(parts, " "), ";\n")
                    else
                        local parts = {}
                        for subk, subv in pairs(v) do
                            table.insert(parts, tostring(subk) .. "=" .. tostring(subv))
                        end
                        file:write("    ", k, " ", table.concat(parts, " "), ";\n")
                    end
                end
            end
        end

        file:write("}\n\n")

        ::continue_upstream::
    end

    file:close()
    return true, nil
end

-- GET /upstreams - 获取所有upstream配置
function _M.list(context)
    local config, err = load_config()
    if not config then
        return context.response.error(err, 500)
    end
    
    local upstreams = {}
    
    for name, upstream_config in pairs(config.upstreams or {}) do
        table.insert(upstreams, {
            name = name,
            servers = upstream_config.servers,
            balance_method = upstream_config.balance_method,
            health_check = upstream_config.health_check,
            enable = upstream_config.enable -- TODO: 获取实际状态
        })
    end
    
    return context.response.success(upstreams)
end

-- GET /upstreams/{name} - 获取单个upstream配置
function _M.get(context)
    local upstream_name = context.params.name
    
    local config, err = load_config()
    if not config then
        return context.response.error(err, 500)
    end
    
    if not config.upstreams or not config.upstreams[upstream_name] then
        return context.response.error("Upstream not found", 404)
    end
    
    local upstream_config = config.upstreams[upstream_name]
    
    return context.response.success(upstream_config)
end

-- POST /upstreams - 创建新的upstream配置
function _M.create(context)
    local data = context.body
    local upstream_name = data.name
    
    if not upstream_name then
        return context.response.error("Upstream name is required", 400)
    end
    
    local config, err = load_config()
    if not config then
        config = {upstreams = {}}
    end
    
    if not config.upstreams then
        config.upstreams = {}
    end
    
    -- 检查是否已存在
    if config.upstreams[upstream_name] then
        return context.response.error("Upstream already exists", 409)
    end
    
    -- 检查服务器状态，如果没有启用的服务器则强制设置 enable 为 false
    if not has_enabled_servers(data) then
        data.enable = false
        ngx.log(ngx.INFO, "No enabled servers found for upstream " .. upstream_name .. ", setting enable to false")
    end
    
    -- 添加默认值
    data.created_at = ngx.time()
    data.updated_at = ngx.time()
    data.created_by = context.user and context.user.id or "system"
    
    -- 处理health_check中的http_req参数
    data = process_health_check(data)
    
    config.upstreams[upstream_name] = data
    
    local success, save_err = save_config(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. save_err, 500)
    end

    -- 保存成功后，生成 upstream.conf
    local ok_conf, conf_err = write_upstream_conf(config)
    if not ok_conf then
        ngx.log(ngx.ERR, conf_err)
        -- 不阻断流程，但返回时提示
        data.warning = conf_err
    end

    -- 调用 nginx -t 验证配置
    local ok_test, err_log = command.nginx_test()
    if not ok_test then
        data.enable = false
        config.upstreams[upstream_name].enable = false
        save_config(config)
        write_upstream_conf(config)

        return context.response.error("Nginx config test failed; upstream has been disabled automatically", 500, err_log)
    end
    
    -- 成功后热重载 Nginx
    local rl_ok, rl_result = command.nginx_reload()
    if not rl_ok then
        if ngx and ngx.log then ngx.log(ngx.ERR, "nginx reload failed: " .. cjson.encode(rl_result)) end
    end

    -- 构建返回数据，nginx 相关信息放在 detail 中
    local response_detail = {
        nginx_test_output = err_log,
        reload_result = rl_result
    }
    if not rl_ok then
        response_detail.reload_warning = rl_result.stderr or rl_result.reason
    end

    return context.response.success(data, "Upstream created successfully", 201, response_detail)
end

-- PUT /upstreams/{name} - 更新upstream配置
function _M.update(context)
    local upstream_name = context.params.name
    local data = context.body
    
    local config, err = load_config()
    if not config then
        return context.response.error(err, 500)
    end
    
    if not config.upstreams or not config.upstreams[upstream_name] then
        return context.response.error("Upstream not found", 404)
    end
    
    -- 保留创建信息，更新其他字段
    local existing = config.upstreams[upstream_name]
    data.name = upstream_name
    data.created_at = existing.created_at
    data.created_by = existing.created_by
    data.updated_at = ngx.time()
    data.updated_by = context.user and context.user.id or "system"
    
    -- 处理health_check中的http_req参数
    data = process_health_check(data)
    
    -- 检查服务器状态，如果没有启用的服务器则强制设置 enable 为 false
    if not has_enabled_servers(data) then
        data.enable = false
        ngx.log(ngx.INFO, "No enabled servers found for upstream " .. upstream_name .. ", setting enable to false")
    end
    
    config.upstreams[upstream_name] = data
    
    local success, save_err = save_config(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. save_err, 500)
    end
    
    -- 重新生成 upstream.conf
    local ok_conf, conf_err = write_upstream_conf(config)
    if not ok_conf then
        ngx.log(ngx.ERR, conf_err)
    end

    -- 测试 nginx 配置
    local ok_test, err_log = command.nginx_test()
    if not ok_test then
        data.enable = false
        config.upstreams[upstream_name].enable = false
        save_config(config)
        write_upstream_conf(config)

        return context.response.error("Nginx config test failed; upstream has been disabled automatically", 500, err_log)
    end

    local rl_ok, rl_result = command.nginx_reload()
    if not rl_ok then
        if ngx and ngx.log then ngx.log(ngx.ERR, "nginx reload failed: " .. cjson.encode(rl_result)) end
    end

    -- 构建返回数据，nginx 相关信息放在 detail 中
    local response_detail = {
        nginx_test_output = err_log,
        reload_result = rl_result
    }
    if not rl_ok then
        response_detail.reload_warning = rl_result.stderr or rl_result.reason
    end

    return context.response.success(data, "Upstream updated successfully", response_detail)
end

-- DELETE /upstreams/{name} - 删除upstream配置
function _M.delete(context)
    local upstream_name = context.params.name
    
    local config, err = load_config()
    if not config then
        return context.response.error(err, 500)
    end
    
    if not config.upstreams or not config.upstreams[upstream_name] then
        return context.response.error("Upstream not found", 404)
    end
    
    config.upstreams[upstream_name] = nil
    
    local success, save_err = save_config(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. save_err, 500)
    end
    
    -- 重新生成 upstream.conf
    local ok_conf, conf_err = write_upstream_conf(config)
    if not ok_conf then
        ngx.log(ngx.ERR, conf_err)
    end

    -- 测试 nginx 配置
    local ok_test, err_log = command.nginx_test()
    if not ok_test then
        return context.response.error("Nginx config test failed", 500, err_log)
    end

    local rl_ok, rl_result = command.nginx_reload()
    if not rl_ok then
        if ngx and ngx.log then ngx.log(ngx.ERR, "nginx reload failed: " .. cjson.encode(rl_result)) end
    end

    -- 构建返回数据，nginx 相关信息放在 detail 中
    local response_data = { deleted_upstream = upstream_name }
    local response_detail = {
        nginx_test_output = err_log,
        reload_result = rl_result
    }
    if not rl_ok then
        response_detail.reload_warning = rl_result.stderr or rl_result.reason
    end

    return context.response.success(response_data, "Upstream deleted successfully", 200, response_detail)
end

function _M.status(context)
    local hc = require "resty.upstream.healthcheck"
    
    local status_data = {
        worker_pid = ngx.worker.pid(),
        status_page = hc.status_page()
    }
    
    return context.response.success(status_data)
end

function _M.showconf(context)
    local file, err = io.open(UPSTREAM_CONF_FILE, "r")
    if not file then
        return context.response.error("Cannot read upstream conf: " .. (err or "unknown error"), 500)
    end
    
    local content = file:read("*all")
    file:close()    
    return context.response.success({ content = content }, "Upstream configuration loaded successfully")
end

return _M 