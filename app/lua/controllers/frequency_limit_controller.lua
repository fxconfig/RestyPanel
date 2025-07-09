-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Frequency Limit Configuration Controller

local cjson = require "cjson"
local config = require "core.config"

local _M = {}

-- 获取所有频率限制规则
function _M.list(context)
    local frequency_config = config.configs.frequency_limit or {}
    local rules = frequency_config.rules or {}
    
    local rule_list = {}
    for i, rule in ipairs(rules) do
        table.insert(rule_list, {
            id = i,
            matcher = rule.matcher,
            count = rule.count or 100,
            period = rule.period or 60,
            action = rule.action or "deny",
            code = rule.code or 429,
            response = rule.response,
            enable = rule.enable or false,
            description = rule.description or "",
            created_at = rule.created_at or 0,
            updated_at = rule.updated_at or 0
        })
    end
    
    -- 支持筛选和搜索
    local search = context.query.search or ""
    local enabled_filter = context.query.enabled
    
    if enabled_filter then
        local enabled = enabled_filter == "true"
        local filtered = {}
        for _, rule in ipairs(rule_list) do
            if rule.enable == enabled then
                table.insert(filtered, rule)
            end
        end
        rule_list = filtered
    end
    
    if search ~= "" then
        local filtered = {}
        for _, rule in ipairs(rule_list) do
            if string.find(rule.matcher or "", search, 1, true) or 
               string.find(rule.description or "", search, 1, true) then
                table.insert(filtered, rule)
            end
        end
        rule_list = filtered
    end
    
    -- 分页
    local page = tonumber(context.query.page) or 1
    local limit = tonumber(context.query.limit) or 20
    local total = #rule_list
    local start_idx = (page - 1) * limit + 1
    local end_idx = math.min(start_idx + limit - 1, total)
    
    local paginated_list = {}
    for i = start_idx, end_idx do
        if rule_list[i] then
            table.insert(paginated_list, rule_list[i])
        end
    end
    
    local pagination = {
        page = page,
        limit = limit,
        total = total,
        pages = math.ceil(total / limit)
    }
    
    -- 添加统计信息
    local stats = {
        total_rules = #rules,
        enabled_rules = 0,
        global_enabled = frequency_config.enable or false
    }
    
    for _, rule in ipairs(rules) do
        if rule.enable then
            stats.enabled_rules = stats.enabled_rules + 1
        end
    end
    
    return context.response.success({
        rules = paginated_list,
        pagination = pagination,
        stats = stats
    })
end

-- 获取单个频率限制规则
function _M.get(context)
    local rule_id = tonumber(context.params.id)
    local frequency_config = config.configs.frequency_limit or {}
    local rules = frequency_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Frequency limit rule not found", 404)
    end
    
    local rule = rules[rule_id]
    local rule_data = {
        id = rule_id,
        matcher = rule.matcher,
        count = rule.count or 100,
        period = rule.period or 60,
        action = rule.action or "deny",
        code = rule.code or 429,
        response = rule.response,
        enable = rule.enable or false,
        description = rule.description or "",
        created_at = rule.created_at or 0,
        updated_at = rule.updated_at or 0
    }
    
    return context.response.success(rule_data)
end

-- 创建新的频率限制规则
function _M.create(context)
    local data = context.body
    
    if not data.matcher then
        return context.response.error("Matcher is required", 400)
    end
    
    if not data.count or tonumber(data.count) <= 0 then
        return context.response.error("Count must be a positive number", 400)
    end
    
    if not data.period or tonumber(data.period) <= 0 then
        return context.response.error("Period must be a positive number", 400)
    end
    
    -- 验证matcher是否存在
    local matchers = config.configs.matcher or {}
    if not matchers[data.matcher] then
        return context.response.error("Matcher '" .. data.matcher .. "' does not exist", 400)
    end
    
    local frequency_config = config.configs.frequency_limit or {}
    if not frequency_config.rules then
        frequency_config.rules = {}
    end
    
    local new_rule = {
        matcher = data.matcher,
        count = tonumber(data.count),
        period = tonumber(data.period),
        action = data.action or "deny",
        code = data.code or 429,
        response = data.response,
        enable = data.enable or false,
        description = data.description or "",
        created_at = ngx.time(),
        updated_at = ngx.time(),
        created_by = context.user and context.user.id or "system"
    }
    
    table.insert(frequency_config.rules, new_rule)
    config.configs.frequency_limit = frequency_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    new_rule.id = #frequency_config.rules
    return context.response.success(new_rule, "Frequency limit rule created successfully", 201)
end

-- 更新频率限制规则
function _M.update(context)
    local rule_id = tonumber(context.params.id)
    local data = context.body
    local frequency_config = config.configs.frequency_limit or {}
    local rules = frequency_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Frequency limit rule not found", 404)
    end
    
    local existing = rules[rule_id]
    
    -- 验证参数
    if data.count and tonumber(data.count) <= 0 then
        return context.response.error("Count must be a positive number", 400)
    end
    
    if data.period and tonumber(data.period) <= 0 then
        return context.response.error("Period must be a positive number", 400)
    end
    
    -- 验证matcher是否存在（如果要更新）
    if data.matcher then
        local matchers = config.configs.matcher or {}
        if not matchers[data.matcher] then
            return context.response.error("Matcher '" .. data.matcher .. "' does not exist", 400)
        end
    end
    
    local updated_rule = {
        matcher = data.matcher or existing.matcher,
        count = tonumber(data.count) or existing.count or 100,
        period = tonumber(data.period) or existing.period or 60,
        action = data.action or existing.action or "deny",
        code = data.code or existing.code or 429,
        response = data.response or existing.response,
        enable = data.enable ~= nil and data.enable or existing.enable,
        description = data.description or existing.description or "",
        created_at = existing.created_at,
        created_by = existing.created_by,
        updated_at = ngx.time(),
        updated_by = context.user and context.user.id or "system"
    }
    
    rules[rule_id] = updated_rule
    config.configs.frequency_limit.rules = rules
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    updated_rule.id = rule_id
    return context.response.success(updated_rule, "Frequency limit rule updated successfully")
end

-- 删除频率限制规则
function _M.delete(context)
    local rule_id = tonumber(context.params.id)
    local frequency_config = config.configs.frequency_limit or {}
    local rules = frequency_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Frequency limit rule not found", 404)
    end
    
    table.remove(rules, rule_id)
    config.configs.frequency_limit.rules = rules
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({}, "Frequency limit rule deleted successfully")
end

-- 启用/禁用频率限制规则
function _M.toggle(context)
    local rule_id = tonumber(context.params.id)
    local frequency_config = config.configs.frequency_limit or {}
    local rules = frequency_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Frequency limit rule not found", 404)
    end
    
    local rule = rules[rule_id]
    rule.enable = not rule.enable
    rule.updated_at = ngx.time()
    rule.updated_by = context.user and context.user.id or "system"
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        id = rule_id,
        enable = rule.enable
    }, "Frequency limit rule " .. (rule.enable and "enabled" or "disabled") .. " successfully")
end

-- 启用/禁用整个频率限制功能
function _M.toggle_global(context)
    local frequency_config = config.configs.frequency_limit or {}
    frequency_config.enable = not frequency_config.enable
    config.configs.frequency_limit = frequency_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        enable = frequency_config.enable
    }, "Frequency limit " .. (frequency_config.enable and "enabled" or "disabled") .. " globally")
end

-- 获取频率限制统计信息
function _M.stats(context)
    -- 这里应该从shared memory中获取实际的统计数据
    -- 为了演示，我们返回模拟数据
    local stats = {
        current_limits = {},
        top_limited_ips = {},
        recent_blocks = 0,
        total_requests = 0
    }
    
    -- 如果有shared memory访问，可以获取实时统计
    local shared_dict = ngx.shared.frequency_limit
    if shared_dict then
        local keys = shared_dict:get_keys(100)
        for _, key in ipairs(keys) do
            local count = shared_dict:get(key)
            if count then
                table.insert(stats.current_limits, {
                    key = key,
                    count = count,
                    timestamp = ngx.time()
                })
            end
        end
    end
    
    return context.response.success(stats)
end

-- 清除频率限制计数器
function _M.clear_counters(context)
    local shared_dict = ngx.shared.frequency_limit
    if shared_dict then
        shared_dict:flush_all()
    end
    
    return context.response.success({}, "Frequency limit counters cleared successfully")
end

-- 保存配置到文件
function _M.save_config()
    return config.dump_to_file(config.configs)
end

return _M 