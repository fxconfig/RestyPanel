-- -*- coding: utf-8 -*-
-- @Date    : 2024-03-21
-- @Author  : Assistant
-- @Link    : 
-- @Disc    : Keepalive module for VeryNginx

local _M = {}
local VeryNginxConfig = require "VeryNginxConfig"
local http = require "resty.http"
local json = require "json"

-- 定义共享内存的键
local KEY_NODE_STATUS = "NODE_STATUS_"  -- 节点状态前缀
local KEY_NODE_LAST_CHECK = "NODE_LAST_CHECK_"  -- 最后检查时间前缀
local KEY_NODE_LAST_ERROR = "NODE_LAST_ERROR_"  -- 最后错误信息前缀



local function split(str, sep)
    if not str then return {} end
    local fields = {}
    local pattern = string.format("([^%s]+)", sep or " ")
    str:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

-- 获取所有节点状态
function _M.get_all_nodes_status()
    local all_status = {}
    local upstreams = VeryNginxConfig.configs.backend_upstream or {}
    
    for upstream_name, upstream in pairs(upstreams) do
        if upstream.node then
            all_status[upstream_name] = {}
            for node_name, node_config in pairs(upstream.node) do
                local node_id = upstream_name .. ":" .. node_name
                local status = {
                    is_healthy = ngx.shared.status:get(KEY_NODE_STATUS .. node_id),
                    last_check = ngx.shared.status:get(KEY_NODE_LAST_CHECK .. node_id),
                    last_error = ngx.shared.status:get(KEY_NODE_LAST_ERROR .. node_id),
                    host = node_config.host,
                    port = node_config.port,
                    scheme = node_config.scheme,
                    enable = node_config.enable
                }
                all_status[upstream_name][node_name] = status
            end
        end
    end
    
    return json.encode(all_status)
end


function _M.check_node(rule)
    if not rule.enable then
        return
    end

    local node = rule.node
    local interval = tonumber(rule.interval) or 30
    local timeout = tonumber(rule.timeout) or 5
    local check_url = rule.check_url or "/"

    -- Parse node address
    local parts = split(node, ":")
    if #parts ~= 2 then
        ngx.log(ngx.ERR, "Invalid node format: ", node)
        return
    end
 
    local upstream_name = parts[1]
    local node_name = parts[2]
    local upstream = VeryNginxConfig.configs.backend_upstream[upstream_name]
    
    if not upstream or not upstream.node or not upstream.node[node_name] then
        ngx.log(ngx.ERR, "Node not found: ", node)
        return
    end

    local host = upstream.node[node_name].host
    local port = upstream.node[node_name].port
    local scheme = upstream.node[node_name].scheme

    -- 创建 HTTP 客户端实例
    local httpc = http.new()
    httpc:set_timeout(timeout * 1000)  -- 设置超时时间（毫秒）
    -- 尝试建立连接
    local ok, err = httpc:connect(host, port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to node ", node, ": ", err)
        -- 更新节点状态为不健康
        ngx.shared.status:set(KEY_NODE_STATUS .. node, false)
        ngx.shared.status:set(KEY_NODE_LAST_CHECK .. node, ngx.time())
        ngx.shared.status:set(KEY_NODE_LAST_ERROR .. node, "Connection failed: " .. (err or "unknown error"))
        return
    end
    -- Make HTTP request to check node health
    local res, err = httpc:request({
        method = "GET",
        path = check_url,
        headers = {
            ["Host"] = host,
            ["User-Agent"] = "VeryNginx/1.0"
        },
        host = host,
        port = port
    })
    -- 确保关闭连接
    httpc:close()
    
    if not res then
        ngx.log(ngx.ERR, "Failed to check node ", node, ": ", err)
        -- 更新节点状态为不健康
        ngx.shared.status:set(KEY_NODE_STATUS .. node, false)
        ngx.shared.status:set(KEY_NODE_LAST_ERROR .. node, "Request failed: " .. (err or "unknown error"))
        return
    end

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Node ", node, " returned status ", res.status)
        -- 更新节点状态为不健康
        ngx.shared.status:set(KEY_NODE_STATUS .. node, false)
        ngx.shared.status:set(KEY_NODE_LAST_ERROR .. node, "HTTP status: " .. res.status)
        return
    end
    -- 更新节点状态为健康
    ngx.shared.status:set(KEY_NODE_STATUS .. node, true)
    ngx.shared.status:set(KEY_NODE_LAST_ERROR .. node, nil)
    ngx.log(ngx.INFO, "Node ", node, " is healthy")
end

-- 获取节点状态
function _M.get_node_status(node)
    local status = {
        is_healthy = ngx.shared.status:get(KEY_NODE_STATUS .. node),
        last_check = ngx.shared.status:get(KEY_NODE_LAST_CHECK .. node),
        last_error = ngx.shared.status:get(KEY_NODE_LAST_ERROR .. node)
    }
    return status
end

function _M.init()
    if not VeryNginxConfig.configs.keepalive_enable then
        return
    end

    local rules = VeryNginxConfig.configs.keepalive_rule
    if not rules then
        return
    end

    for _, rule in ipairs(rules) do
        if rule.enable then
            local interval = tonumber(rule.interval) or 30
            ngx.timer.every(interval, _M.check_node, rule)
        end
    end
end

-- 生成 upstream.conf 文件
function _M.generate_upstream_conf(healthy_only)
    local upstreams = VeryNginxConfig.configs.backend_upstream or {}
    local lines = {}
    for upstream_name, upstream in pairs(upstreams) do
        if upstream.node then
            local node_lines = {}
            for node_name, node_config in pairs(upstream.node) do
                local node_id = upstream_name .. ":" .. node_name
                local is_healthy = ngx.shared.status:get(KEY_NODE_STATUS .. node_id)
                if (not healthy_only) or is_healthy then
                    local host = node_config.host
                    local port = node_config.port or 80
                    table.insert(node_lines, string.format("  server %s:%s;", host, port))
                end
            end
            if #node_lines > 0 then
                table.insert(lines, string.format("upstream %s {", upstream_name))
                for _, l in ipairs(node_lines) do
                    table.insert(lines, l)
                end
                table.insert(lines, "}")
            end
            -- 如果 node_lines 为空，则不生成该 upstream
        end
    end
    local content = table.concat(lines, "\n")
    local new_md5 = ngx.md5(content)
    local last_md5 = ngx.shared.status:get('vn_upstream_conf_md5')
    if new_md5 == last_md5 then
        ngx.log(ngx.INFO, "upstream.conf md5 not changed, skip writing file.")
        return true, "not changed"
    end
    --local file_path = ngx.config.prefix() .. "/../verynginx/nginx_conf/upstream.conf"
    local file_path = "/opt/verynginx/verynginx/nginx_conf/upstream.conf"
    local file, err = io.open(file_path, "w")
    if not file then
        ngx.log(ngx.ERR, "Failed to open upstream.conf for writing: ", err)
        return false, err
    end
    file:write(content)
    file:close()
    ngx.shared.status:set('vn_upstream_conf_md5', new_md5)
    ngx.log(ngx.INFO, "upstream.conf generated at ", file_path)
    -- 自动 reload nginx
    local reload_ret = os.execute("/opt/verynginx/openresty/nginx/sbin/nginx -s reload")
    if reload_ret == 0 then
        ngx.log(ngx.INFO, "nginx reload success after upstream.conf update")
    else
        ngx.log(ngx.ERR, "nginx reload failed after upstream.conf update, ret=", reload_ret)
    end
    return true
end

return _M