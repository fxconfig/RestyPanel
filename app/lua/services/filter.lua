-- -*- coding: utf-8 -*-
-- @Date    : 2015-10-25 15:56:46
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : 使用新配置管理系统的filter服务模块

local matcher = require "core.matcher"
local config_helper = require "core.config_helper"

local _M = {}

-- 创建配置接口
local filter_config = config_helper.create_config_interface("filter")
local matcher_config = config_helper.create_config_interface("matcher")

function _M.filter()
    -- 获取filter配置
    local config = filter_config.get()
    
    if not config or config.enable ~= true then
        return
    end

    -- 获取matcher配置
    local matcher_list = matcher_config.get()
    
    local rules = config.rules or {}
    
    for i, rule in ipairs(rules) do
        local enable = rule.enable
        local matcher_config_data = matcher_list[rule.matcher]
        
        if enable == true and matcher.test(matcher_config_data) == true then
            if rule.action == 'block' then
                local code = rule.code or 403
                ngx.exit(tonumber(code))
            end
            return
        end
    end
end

-- 获取过滤统计信息
function _M.get_stats()
    local config = filter_config.get()
    local rules = config.rules or {}
    
    local stats = {
        total_rules = #rules,
        enabled_rules = 0,
        blocked_rules = 0,
        accept_rules = 0
    }
    
    for _, rule in ipairs(rules) do
        if rule.enable then
            stats.enabled_rules = stats.enabled_rules + 1
            if rule.action == "block" then
                stats.blocked_rules = stats.blocked_rules + 1
            elseif rule.action == "accept" then
                stats.accept_rules = stats.accept_rules + 1
            end
        end
    end
    
    return stats
end

-- 重新加载配置
function _M.reload_config()
    local config, err = filter_config.reload()
    if err then
        ngx.log(ngx.ERR, "Failed to reload filter config: " .. err)
        return false, err
    end
    
    ngx.log(ngx.INFO, "Filter configuration reloaded successfully")
    return true, nil
end

-- 获取配置状态
function _M.get_config_status()
    local config = require "core.config"
    local status = config.get_all_modules_status()
    
    return {
        filter_status = status.filter,
        matcher_status = status.matcher,
        timestamp = ngx.time()
    }
end

return _M 