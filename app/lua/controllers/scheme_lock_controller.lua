-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Scheme Lock Configuration Controller

local cjson = require "cjson"
local config = require "core.config"

local _M = {}

-- 获取所有协议锁定规则
function _M.list(context)
    local scheme_lock_config = config.configs.scheme_lock or {}
    local rules = scheme_lock_config.rules or {}
    
    local rule_list = {}
    for i, rule in ipairs(rules) do
        table.insert(rule_list, {
            id = i,
            matcher = rule.matcher,
            scheme = rule.scheme,
            action = rule.action or "deny",
            code = rule.code or 403,
            enable = rule.enable or false,
            description = rule.description or "",
            created_at = rule.created_at or 0,
            updated_at = rule.updated_at or 0
        })
    end
    
    -- 支持筛选和搜索
    local search = context.query.search or ""
    local enabled_filter = context.query.enabled
    local scheme_filter = context.query.scheme
    
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
    
    if scheme_filter then
        local filtered = {}
        for _, rule in ipairs(rule_list) do
            if rule.scheme == scheme_filter then
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
        https_rules = 0,
        http_rules = 0,
        global_enabled = scheme_lock_config.enable or false
    }
    
    for _, rule in ipairs(rules) do
        if rule.enable then
            stats.enabled_rules = stats.enabled_rules + 1
            if rule.scheme == "https" then
                stats.https_rules = stats.https_rules + 1
            elseif rule.scheme == "http" then
                stats.http_rules = stats.http_rules + 1
            end
        end
    end
    
    return context.response.success({
        rules = paginated_list,
        pagination = pagination,
        stats = stats
    })
end

-- 获取单个协议锁定规则
function _M.get(context)
    local rule_id = tonumber(context.params.id)
    local scheme_lock_config = config.configs.scheme_lock or {}
    local rules = scheme_lock_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Scheme lock rule not found", 404)
    end
    
    local rule = rules[rule_id]
    local rule_data = {
        id = rule_id,
        matcher = rule.matcher,
        scheme = rule.scheme,
        action = rule.action or "deny",
        code = rule.code or 403,
        enable = rule.enable or false,
        description = rule.description or "",
        created_at = rule.created_at or 0,
        updated_at = rule.updated_at or 0
    }
    
    return context.response.success(rule_data)
end

-- 创建新的协议锁定规则
function _M.create(context)
    local data = context.body
    
    if not data.matcher then
        return context.response.error("Matcher is required", 400)
    end
    
    if not data.scheme then
        return context.response.error("Scheme is required", 400)
    end
    
    if data.scheme ~= "http" and data.scheme ~= "https" then
        return context.response.error("Scheme must be 'http' or 'https'", 400)
    end
    
    -- 验证action
    if data.action and data.action ~= "deny" and data.action ~= "redirect" then
        return context.response.error("Action must be 'deny' or 'redirect'", 400)
    end
    
    -- 验证matcher是否存在
    local matchers = config.configs.matcher or {}
    if not matchers[data.matcher] then
        return context.response.error("Matcher '" .. data.matcher .. "' does not exist", 400)
    end
    
    local scheme_lock_config = config.configs.scheme_lock or {}
    if not scheme_lock_config.rules then
        scheme_lock_config.rules = {}
    end
    
    local new_rule = {
        matcher = data.matcher,
        scheme = data.scheme,
        action = data.action or "deny",
        code = data.code or 403,
        enable = data.enable or false,
        description = data.description or "",
        created_at = ngx.time(),
        updated_at = ngx.time(),
        created_by = context.user and context.user.id or "system"
    }
    
    table.insert(scheme_lock_config.rules, new_rule)
    config.configs.scheme_lock = scheme_lock_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    new_rule.id = #scheme_lock_config.rules
    return context.response.success(new_rule, "Scheme lock rule created successfully", 201)
end

-- 更新协议锁定规则
function _M.update(context)
    local rule_id = tonumber(context.params.id)
    local data = context.body
    local scheme_lock_config = config.configs.scheme_lock or {}
    local rules = scheme_lock_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Scheme lock rule not found", 404)
    end
    
    local existing = rules[rule_id]
    
    -- 验证scheme
    if data.scheme and data.scheme ~= "http" and data.scheme ~= "https" then
        return context.response.error("Scheme must be 'http' or 'https'", 400)
    end
    
    -- 验证action
    if data.action and data.action ~= "deny" and data.action ~= "redirect" then
        return context.response.error("Action must be 'deny' or 'redirect'", 400)
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
        scheme = data.scheme or existing.scheme,
        action = data.action or existing.action or "deny",
        code = data.code or existing.code or 403,
        enable = data.enable ~= nil and data.enable or existing.enable,
        description = data.description or existing.description or "",
        created_at = existing.created_at,
        created_by = existing.created_by,
        updated_at = ngx.time(),
        updated_by = context.user and context.user.id or "system"
    }
    
    rules[rule_id] = updated_rule
    config.configs.scheme_lock.rules = rules
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    updated_rule.id = rule_id
    return context.response.success(updated_rule, "Scheme lock rule updated successfully")
end

-- 删除协议锁定规则
function _M.delete(context)
    local rule_id = tonumber(context.params.id)
    local scheme_lock_config = config.configs.scheme_lock or {}
    local rules = scheme_lock_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Scheme lock rule not found", 404)
    end
    
    table.remove(rules, rule_id)
    config.configs.scheme_lock.rules = rules
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({}, "Scheme lock rule deleted successfully")
end

-- 启用/禁用协议锁定规则
function _M.toggle(context)
    local rule_id = tonumber(context.params.id)
    local scheme_lock_config = config.configs.scheme_lock or {}
    local rules = scheme_lock_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Scheme lock rule not found", 404)
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
    }, "Scheme lock rule " .. (rule.enable and "enabled" or "disabled") .. " successfully")
end

-- 启用/禁用整个协议锁定功能
function _M.toggle_global(context)
    local scheme_lock_config = config.configs.scheme_lock or {}
    scheme_lock_config.enable = not scheme_lock_config.enable
    config.configs.scheme_lock = scheme_lock_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        enable = scheme_lock_config.enable
    }, "Scheme lock " .. (scheme_lock_config.enable and "enabled" or "disabled") .. " globally")
end

-- 测试协议锁定规则
function _M.test(context)
    local rule_id = tonumber(context.params.id)
    local test_data = context.body or {}  -- 确保 test_data 不为 nil
    
    local scheme_lock_config = config.configs.scheme_lock or {}
    local rules = scheme_lock_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Scheme lock rule not found", 404)
    end
    
    local rule = rules[rule_id]
    local matchers = config.configs.matcher or {}
    local matcher = matchers[rule.matcher]
    
    if not matcher then
        return context.response.error("Matcher not found", 404)
    end
    
    -- 准备测试上下文
    local test_context = {
        uri = test_data.uri or "/",
        method = test_data.method or "GET",
        headers = test_data.headers or {},
        args = test_data.args or {},
        ip = test_data.ip or "127.0.0.1",
        scheme = test_data.scheme or "http",
        host = test_data.host or "localhost"
    }
    
    -- 模拟协议检查
    local test_scheme = test_context.scheme
    local scheme_matches = (test_scheme == rule.scheme)
    
    -- 使用matcher模块进行匹配测试
    local matcher_lib = require "core.matcher"
    local match_result = matcher_lib.test(matcher, test_context)
    
    local test_result = {
        rule_id = rule_id,
        matcher = rule.matcher,
        required_scheme = rule.scheme,
        test_input = test_context,
        match_result = match_result,
        scheme_matches = scheme_matches,
        would_trigger = match_result and rule.enable and not scheme_matches,
        action = rule.action,
        timestamp = ngx.time()
    }
    
    -- 如果是重定向模式，添加重定向URL
    if rule.action == "redirect" and not scheme_matches then
        local redirect_url = rule.scheme .. "://" .. test_context.host .. test_context.uri
        test_result.redirect_to = redirect_url
    end
    
    return context.response.success(test_result)
end

-- 保存配置到文件
function _M.save_config()
    return config.dump_to_file(config.configs)
end

return _M 