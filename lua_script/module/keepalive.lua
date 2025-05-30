-- -*- coding: utf-8 -*-
-- @Date    : 2024-03-21
-- @Author  : Assistant
-- @Link    : 
-- @Disc    : Keepalive module for VeryNginx

local _M = {}
local VeryNginxConfig = require "VeryNginxConfig"
local http = require "resty.http"
local function split(str, sep)
    if not str then return {} end
    local fields = {}
    local pattern = string.format("([^%s]+)", sep or " ")
    str:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
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

    local node = "skynet"
    local host = "127.0.0.1"
    local port = 7777
    local scheme = "http"
    local timeout = 5

        -- 使用 ngx.location.capture 进行健康检查
    local res = ngx.location.capture("/internal_health_check", {
            args = {
                backend = "127.0.0.1:7777",
                path = "/ping"
            },
            method = ngx.HTTP_GET
        })
    

    if not res then
        ngx.log(ngx.ERR, "Failed to check node ", node, ": ", err)
        return
    end

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Node ", node, " returned status ", res.status)
        return
    end

    ngx.log(ngx.INFO, "Node ", node, " is healthy")
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

return _M