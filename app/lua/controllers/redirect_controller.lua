-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Redirect Rules Configuration Controller

local cjson = require "cjson"
local config = require "core.config"

local _M = {}

-- 获取所有重定向规则
function _M.list(context)
    local redirect_config = config.configs.redirect or {}
    local rules = redirect_config.rules or {}
    
    local rule_list = {}
    for i, rule in ipairs(rules) do
        table.insert(rule_list, {
            id = i,
            matcher = rule.matcher,
            to_uri = rule.to_uri,
            replace_re = rule.replace_re,
            code = rule.code or 302,
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
               string.find(rule.to_uri or "", search, 1, true) or
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
        global_enabled = redirect_config.enable or false
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

-- 获取单个重定向规则
function _M.get(context)
    local rule_id = tonumber(context.params.id)
    local redirect_config = config.configs.redirect or {}
    local rules = redirect_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Redirect rule not found", 404)
    end
    
    local rule = rules[rule_id]
    local rule_data = {
        id = rule_id,
        matcher = rule.matcher,
        to_uri = rule.to_uri,
        replace_re = rule.replace_re,
        code = rule.code or 302,
        enable = rule.enable or false,
        description = rule.description or "",
        created_at = rule.created_at or 0,
        updated_at = rule.updated_at or 0
    }
    
    return context.response.success(rule_data)
end

-- 创建新的重定向规则
function _M.create(context)
    local data = context.body
    
    if not data.matcher then
        return context.response.error("Matcher is required", 400)
    end
    
    if not data.to_uri then
        return context.response.error("Target URI is required", 400)
    end
    
    -- 验证HTTP状态码
    if data.code and (tonumber(data.code) < 300 or tonumber(data.code) >= 400) then
        return context.response.error("Redirect code must be between 300-399", 400)
    end
    
    -- 验证matcher是否存在
    local matchers = config.configs.matcher or {}
    if not matchers[data.matcher] then
        return context.response.error("Matcher '" .. data.matcher .. "' does not exist", 400)
    end
    
    local redirect_config = config.configs.redirect or {}
    if not redirect_config.rules then
        redirect_config.rules = {}
    end
    
    local new_rule = {
        matcher = data.matcher,
        to_uri = data.to_uri,
        replace_re = data.replace_re,
        code = tonumber(data.code) or 302,
        enable = data.enable or false,
        description = data.description or "",
        created_at = ngx.time(),
        updated_at = ngx.time(),
        created_by = context.user and context.user.id or "system"
    }
    
    table.insert(redirect_config.rules, new_rule)
    config.configs.redirect = redirect_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    new_rule.id = #redirect_config.rules
    return context.response.success(new_rule, "Redirect rule created successfully", 201)
end

-- 更新重定向规则
function _M.update(context)
    local rule_id = tonumber(context.params.id)
    local data = context.body
    local redirect_config = config.configs.redirect or {}
    local rules = redirect_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Redirect rule not found", 404)
    end
    
    local existing = rules[rule_id]
    
    -- 验证HTTP状态码
    if data.code and (tonumber(data.code) < 300 or tonumber(data.code) >= 400) then
        return context.response.error("Redirect code must be between 300-399", 400)
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
        to_uri = data.to_uri or existing.to_uri,
        replace_re = data.replace_re or existing.replace_re,
        code = tonumber(data.code) or existing.code or 302,
        enable = data.enable ~= nil and data.enable or existing.enable,
        description = data.description or existing.description or "",
        created_at = existing.created_at,
        created_by = existing.created_by,
        updated_at = ngx.time(),
        updated_by = context.user and context.user.id or "system"
    }
    
    rules[rule_id] = updated_rule
    config.configs.redirect.rules = rules
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    updated_rule.id = rule_id
    return context.response.success(updated_rule, "Redirect rule updated successfully")
end

-- 删除重定向规则
function _M.delete(context)
    local rule_id = tonumber(context.params.id)
    local redirect_config = config.configs.redirect or {}
    local rules = redirect_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Redirect rule not found", 404)
    end
    
    table.remove(rules, rule_id)
    config.configs.redirect.rules = rules
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({}, "Redirect rule deleted successfully")
end

-- 启用/禁用重定向规则
function _M.toggle(context)
    local rule_id = tonumber(context.params.id)
    local redirect_config = config.configs.redirect or {}
    local rules = redirect_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Redirect rule not found", 404)
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
    }, "Redirect rule " .. (rule.enable and "enabled" or "disabled") .. " successfully")
end

-- 启用/禁用整个重定向功能
function _M.toggle_global(context)
    local redirect_config = config.configs.redirect or {}
    redirect_config.enable = not redirect_config.enable
    config.configs.redirect = redirect_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        enable = redirect_config.enable
    }, "Redirect " .. (redirect_config.enable and "enabled" or "disabled") .. " globally")
end

-- 测试重定向规则
function _M.test(context)
    local rule_id = tonumber(context.params.id)
    local test_data = context.body or {}  -- 确保 test_data 不为 nil
    
    local redirect_config = config.configs.redirect or {}
    local rules = redirect_config.rules or {}
    
    if not rule_id or rule_id < 1 or rule_id > #rules then
        return context.response.error("Redirect rule not found", 404)
    end
    
    local rule = rules[rule_id]
    local matchers = config.configs.matcher or {}
    local matcher = matchers[rule.matcher]
    
    if not matcher then
        return context.response.error("Matcher not found", 404)
    end
    
    -- 使用当前请求的URI进行重定向模拟
    local current_uri = ngx.var.uri
    local result_uri = rule.to_uri
    
    -- 如果有正则替换
    if rule.replace_re and string.len(rule.replace_re) > 0 then
        local success, new_uri = pcall(string.gsub, current_uri, rule.replace_re, rule.to_uri)
        if success then
            result_uri = new_uri
        end
    end
    
    -- 使用matcher模块对当前请求进行匹配测试
    local matcher = require "core.matcher"
    local match_result = matcher.test(matcher)
    
    return context.response.success({
        rule_id = rule_id,
        matcher = rule.matcher,
        match_result = match_result,
        would_trigger = match_result and rule.enable,
        redirect_to = result_uri,
        redirect_code = rule.code,
        timestamp = ngx.time(),
        note = "Testing against current request (test_data parameter no longer supported for performance)"
    })
end

-- 保存配置到文件
function _M.save_config()
    return config.dump_to_file(config.configs)
end

return _M 