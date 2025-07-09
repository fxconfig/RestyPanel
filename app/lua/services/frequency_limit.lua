-- -*- coding: utf-8 -*-
-- @Date    : 2015-10-25 15:56:46
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : 使用新配置管理系统的频率限制服务模块

local util = require "core.util"
local cjson = require "cjson"
local matcher = require "core.matcher"
local config_helper = require "core.config_helper"

local _M = {}

-- 创建配置接口
local frequency_limit_config = config_helper.create_config_interface("frequency_limit")
local matcher_config = config_helper.create_config_interface("matcher")

function _M.filter()
    -- 获取频率限制配置
    local config = frequency_limit_config.get()
    
    if not config or config.enable ~= true then
        return
    end

    local ngx_shared_frequency_limit = ngx.shared.frequency_limit
    local matcher_list = matcher_config.get()
    local rules = config.rules or {}

    for i, rule in ipairs(rules) do
        local enable = rule.enable
        local matcher_config_data = matcher_list[rule.matcher]
        
        if enable == true and matcher.test(matcher_config_data) == true then
            local gen_ident = util.cache_build_key(cjson.encode(matcher_config_data))
            local count = rule.count
            local period = rule.period
            local action = rule.action

            local current_count = ngx_shared_frequency_limit:incr(gen_ident, 1, 0, period)

            if current_count > count then
                if action == 'block' then
                    ngx.exit(403)
                end
            end
            
            return
        end
    end
end

-- 获取频率限制统计信息
function _M.get_stats()
    local config = frequency_limit_config.get()
    local rules = config.rules or {}
    
    local stats = {
        total_rules = #rules,
        enabled_rules = 0,
        active_limits = 0
    }
    
    for _, rule in ipairs(rules) do
        if rule.enable then
            stats.enabled_rules = stats.enabled_rules + 1
        end
    end
    
    -- 获取活跃的限制计数
    local ngx_shared_frequency_limit = ngx.shared.frequency_limit
    if ngx_shared_frequency_limit then
        local keys = ngx_shared_frequency_limit:get_keys(0)
        stats.active_limits = #keys
    end
    
    return stats
end

-- 清除频率限制计数器
function _M.clear_counters()
    local ngx_shared_frequency_limit = ngx.shared.frequency_limit
    if ngx_shared_frequency_limit then
        ngx_shared_frequency_limit:flush_all()
        ngx.log(ngx.INFO, "Frequency limit counters cleared")
        return true
    end
    return false
end

-- 获取特定规则的当前计数
function _M.get_rule_counter(rule_id)
    local config = frequency_limit_config.get()
    local rules = config.rules or {}
    
    if not rules[rule_id] then
        return nil, "Rule not found"
    end
    
    local rule = rules[rule_id]
    local matcher_list = matcher_config.get()
    local matcher_config_data = matcher_list[rule.matcher]
    
    if not matcher_config_data then
        return nil, "Matcher not found"
    end
    
    local gen_ident = util.cache_build_key(cjson.encode(matcher_config_data))
    local ngx_shared_frequency_limit = ngx.shared.frequency_limit
    
    if ngx_shared_frequency_limit then
        local current_count = ngx_shared_frequency_limit:get(gen_ident) or 0
        return {
            rule_id = rule_id,
            current_count = current_count,
            limit = rule.count,
            period = rule.period,
            percentage = (current_count / rule.count) * 100
        }
    end
    
    return nil, "Shared memory not available"
end

-- 重新加载配置
function _M.reload_config()
    local config, err = frequency_limit_config.reload()
    if err then
        ngx.log(ngx.ERR, "Failed to reload frequency limit config: " .. err)
        return false, err
    end
    
    ngx.log(ngx.INFO, "Frequency limit configuration reloaded successfully")
    return true, nil
end

-- 获取配置状态
function _M.get_config_status()
    local config = require "core.config"
    local status = config.get_all_modules_status()
    
    return {
        frequency_limit_status = status.frequency_limit,
        matcher_status = status.matcher,
        timestamp = ngx.time()
    }
end

return _M 