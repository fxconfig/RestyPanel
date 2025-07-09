-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Filter Rules (WAF) Configuration Controller - 使用新的独立配置管理

local cjson = require "cjson"
local config_helper = require "core.config_helper"

local _M = {}

-- 创建配置接口
local filter_config = config_helper.create_config_interface("filter")
local matcher_config = config_helper.create_config_interface("matcher")

-- 获取所有filter规则
function _M.list(context)
    local config = filter_config.get()
    if not config then
        config = {}
    end
    local rules = config.rules or {}
    
    local rule_list = {}
    for i, rule in ipairs(rules) do
        table.insert(rule_list, {
            id = i,
            matcher = rule.matcher,
            action = rule.action,
            code = rule.code or 403,
            response = rule.response,
            enable = rule.enable or false,
            priority = rule.priority or i,
            description = rule.description or "",
            created_at = rule.created_at or 0,
            updated_at = rule.updated_at or 0
        })
    end
    
    -- 支持筛选
    local action_filter = context.query.action
    local enabled_filter = context.query.enabled
    local search = context.query.search or ""
    
    if action_filter then
        local filtered = {}
        for _, rule in ipairs(rule_list) do
            if rule.action == action_filter then
                table.insert(filtered, rule)
            end
        end
        rule_list = filtered
    end
    
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
    
    return context.response.success({
        rules = paginated_list,
        pagination = pagination,
        stats = stats,
        filter_enabled = config.enable or false
    })
end

-- 获取单个filter规则
function _M.get(context)
    local rule_id = tonumber(context.params.id)
    local config = filter_config.get()
    local rules = config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Filter rule not found", 404)
    end
    
    local rule = rules[rule_id]
    local rule_data = {
        id = rule_id,
        matcher = rule.matcher,
        action = rule.action,
        code = rule.code or 403,
        response = rule.response,
        enable = rule.enable or false,
        priority = rule.priority or rule_id,
        description = rule.description or "",
        created_at = rule.created_at or 0,
        updated_at = rule.updated_at or 0
    }
    
    return context.response.success(rule_data)
end

-- 创建新的filter规则
function _M.create(context)
    local data = context.body
    
    if not data.matcher then
        return context.response.error("Matcher is required", 400)
    end
    
    if not data.action then
        return context.response.error("Action is required", 400)
    end
    
    if data.action ~= "block" and data.action ~= "accept" then
        return context.response.error("Action must be 'block' or 'accept'", 400)
    end
    
    -- 验证matcher是否存在
    local matchers = matcher_config.get()
    if not matchers[data.matcher] then
        return context.response.error("Matcher '" .. data.matcher .. "' does not exist", 400)
    end
    
    local config = filter_config.get()
    if not config.rules then
        config.rules = {}
    end
    
    local new_rule = {
        matcher = data.matcher,
        action = data.action,
        code = data.code or 403,
        response = data.response,
        enable = data.enable or false,
        priority = data.priority or (#config.rules + 1),
        description = data.description or "",
        created_at = ngx.time(),
        updated_at = ngx.time(),
        created_by = context.user and context.user.id or "system"
    }
    
    table.insert(config.rules, new_rule)
    
    -- 保存配置到独立文件
    local success, err = filter_config.set(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    new_rule.id = #config.rules
    return context.response.success(new_rule, "Filter rule created successfully", 201)
end

-- 更新filter规则
function _M.update(context)
    local rule_id = tonumber(context.params.id)
    local data = context.body
    local config = filter_config.get()
    local rules = config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Filter rule not found", 404)
    end
    
    local existing = rules[rule_id]
    
    -- 验证matcher是否存在（如果要更新）
    if data.matcher then
        local matchers = matcher_config.get()
        if not matchers[data.matcher] then
            return context.response.error("Matcher '" .. data.matcher .. "' does not exist", 400)
        end
    end
    
    local updated_rule = {
        matcher = data.matcher or existing.matcher,
        action = data.action or existing.action,
        code = data.code or existing.code or 403,
        response = data.response or existing.response,
        enable = data.enable ~= nil and data.enable or existing.enable,
        priority = data.priority or existing.priority or rule_id,
        description = data.description or existing.description or "",
        created_at = existing.created_at,
        created_by = existing.created_by,
        updated_at = ngx.time(),
        updated_by = context.user and context.user.id or "system"
    }
    
    rules[rule_id] = updated_rule
    config.rules = rules
    
    -- 保存配置到独立文件
    local success, err = filter_config.set(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    updated_rule.id = rule_id
    return context.response.success(updated_rule, "Filter rule updated successfully")
end

-- 删除filter规则
function _M.delete(context)
    local rule_id = tonumber(context.params.id)
    local config = filter_config.get()
    local rules = config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Filter rule not found", 404)
    end
    
    table.remove(rules, rule_id)
    config.rules = rules
    
    -- 保存配置到独立文件
    local success, err = filter_config.set(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({}, "Filter rule deleted successfully")
end

-- 启用/禁用filter规则
function _M.toggle(context)
    local rule_id = tonumber(context.params.id)
    local config = filter_config.get()
    local rules = config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Filter rule not found", 404)
    end
    
    local rule = rules[rule_id]
    rule.enable = not rule.enable
    rule.updated_at = ngx.time()
    rule.updated_by = context.user and context.user.id or "system"
    
    -- 保存配置到独立文件
    local success, err = filter_config.set(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        id = rule_id,
        enable = rule.enable
    }, "Filter rule " .. (rule.enable and "enabled" or "disabled") .. " successfully")
end

-- 启用/禁用整个filter功能
function _M.toggle_filter(context)
    local config = filter_config.get()
    config.enable = not config.enable
    
    -- 保存配置到独立文件
    local success, err = filter_config.set(config)
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        enable = config.enable
    }, "Filter " .. (config.enable and "enabled" or "disabled") .. " successfully")
end

-- 重置配置为默认值
function _M.reset_to_default(context)
    local success, err = filter_config.reset()
    if not success then
        return context.response.error("Failed to reset configuration: " .. err, 500)
    end
    
    return context.response.success({}, "Filter configuration reset to default successfully")
end

-- 备份配置
function _M.backup(context)
    local data = context.body
    local backup_name = data.backup_name or ("backup_" .. ngx.time())
    
    local success, backup_path = filter_config.backup(backup_name)
    if not success then
        return context.response.error("Failed to create backup: " .. backup_path, 500)
    end
    
    return context.response.success({
        backup_name = backup_name,
        backup_path = backup_path,
        created_at = ngx.time()
    }, "Configuration backup created successfully")
end

-- 重新加载配置
function _M.reload(context)
    local config, err = filter_config.reload()
    if err then
        return context.response.error("Failed to reload configuration: " .. err, 500)
    end
    
    return context.response.success({
        reloaded_at = ngx.time(),
        rules_count = #(config.rules or {}),
        enabled = config.enable or false
    }, "Configuration reloaded successfully")
end

-- 获取配置状态
function _M.status(context)
    local config = require "core.config"
    local status = config.get_all_modules_status()
    
    return context.response.success({
        filter_status = status.filter,
        matcher_status = status.matcher,
        timestamp = ngx.time()
    })
end

-- 测试filter规则（保持不变）
function _M.test(context)
    local rule_id = tonumber(context.params.id)
    local test_data = context.body or {}
    
    local config = filter_config.get()
    local rules = config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Filter rule not found", 404)
    end
    
    local rule = rules[rule_id]
    local matchers = matcher_config.get()
    local matcher = matchers[rule.matcher]
    
    if not matcher then
        return context.response.error("Matcher not found", 404)
    end
    
    -- 使用matcher模块对当前请求进行测试
    local matcher_lib = require "core.matcher"
    local match_result = matcher_lib.test(matcher)
    
    return context.response.success({
        rule_id = rule_id,
        matcher = rule.matcher,
        action = rule.action,
        match_result = match_result,
        would_trigger = match_result and rule.enable,
        timestamp = ngx.time(),
        note = "Testing against current request (test_data parameter no longer supported for performance)"
    })
end

-- 检查rule被引用的情况  
function _M.check_references(rule_id)
    -- 目前filter规则没有被其他配置引用的情况
    -- 可以根据需要扩展
    return {}
end

return _M 