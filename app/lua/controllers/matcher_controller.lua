-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Matcher Configuration Controller

local cjson = require "cjson"
local config = require "core.config"

local _M = {}

-- 获取所有matcher配置
function _M.list(context)
    local matchers = config.configs.matcher or {}
    
    -- 转换为数组格式便于前端处理
    local matcher_list = {}
    for name, matcher_config in pairs(matchers) do
        table.insert(matcher_list, {
            name = name,
            config = matcher_config,
            created_at = matcher_config.created_at or 0,
            updated_at = matcher_config.updated_at or 0
        })
    end
    
    -- 支持搜索和分页
    local search = context.query.search or ""
    local page = tonumber(context.query.page) or 1
    local limit = tonumber(context.query.limit) or 20
    
    if search ~= "" then
        local filtered = {}
        for _, matcher in ipairs(matcher_list) do
            if string.find(matcher.name, search, 1, true) then
                table.insert(filtered, matcher)
            end
        end
        matcher_list = filtered
    end
    
    local total = #matcher_list
    local start_idx = (page - 1) * limit + 1
    local end_idx = math.min(start_idx + limit - 1, total)
    
    local paginated_list = {}
    for i = start_idx, end_idx do
        table.insert(paginated_list, matcher_list[i])
    end
    
    local pagination = {
        page = page,
        limit = limit,
        total = total,
        pages = math.ceil(total / limit)
    }
    
    return context.response.paginated(paginated_list, pagination)
end

-- 获取单个matcher配置
function _M.get(context)
    local matcher_name = context.params.name
    local matchers = config.configs.matcher or {}
    
    if not matchers[matcher_name] then
        return context.response.error("Matcher not found", 404)
    end
    
    local matcher_data = {
        name = matcher_name,
        config = matchers[matcher_name],
        created_at = matchers[matcher_name].created_at or 0,
        updated_at = matchers[matcher_name].updated_at or 0
    }
    
    return context.response.success(matcher_data)
end

-- 创建新的matcher
function _M.create(context)
    local data = context.body
    local matcher_name = data.name
    
    if not matcher_name then
        return context.response.error("Matcher name is required", 400)
    end
    
    -- 确保matcher配置结构存在
    if not config.configs.matcher then
        config.configs.matcher = {}
    end
    
    local matchers = config.configs.matcher
    
    if matchers[matcher_name] then
        return context.response.error("Matcher already exists", 409)
    end
    
    -- 验证matcher配置格式
    local matcher_config = data.config or {}
    
    -- 添加元数据
    matcher_config.created_at = ngx.time()
    matcher_config.updated_at = ngx.time()
    matcher_config.created_by = context.user and context.user.id or "system"
    
    -- 更新配置
    config.configs.matcher[matcher_name] = matcher_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        ngx.log(ngx.ERR, "Failed to save configuration: " .. (err or "unknown error"))  
        return context.response.error("Failed to save configuration: " .. (err or "unknown error"), 500)
    end
    
    return context.response.success({
        name = matcher_name,
        config = matcher_config
    }, "Matcher created successfully", 201)
end

-- 更新matcher配置
function _M.update(context)
    local matcher_name = context.params.name
    local data = context.body or {}  -- 确保 data 不为 nil
    local matchers = config.configs.matcher or {}
    
    if not matchers[matcher_name] then
        return context.response.error("Matcher not found", 404)
    end
    
    local existing = matchers[matcher_name]
    local updated_config = data.config or {}
    
    -- 保留创建信息
    updated_config.created_at = existing.created_at
    updated_config.created_by = existing.created_by
    updated_config.updated_at = ngx.time()
    updated_config.updated_by = context.user and context.user.id or "system"
    
    config.configs.matcher[matcher_name] = updated_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        name = matcher_name,
        config = updated_config
    }, "Matcher updated successfully")
end

-- 删除matcher
function _M.delete(context)
    local matcher_name = context.params.name
    local matchers = config.configs.matcher or {}
    
    if not matchers[matcher_name] then
        return context.response.error("Matcher not found", 404)
    end
    
    -- 检查是否被其他配置引用
    local references = _M.check_references(matcher_name)
    if #references > 0 then
        return context.response.error("Cannot delete matcher: it is referenced by " .. table.concat(references, ", "), 400)
    end
    
    config.configs.matcher[matcher_name] = nil
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({}, "Matcher deleted successfully")
end

-- 测试matcher匹配
function _M.test(context)
    local matcher_name = context.params.name
    local test_data = context.body or {}  -- 确保 test_data 不为 nil
    
    local matchers = config.configs.matcher or {}
    if not matchers[matcher_name] then
        return context.response.error("Matcher not found", 404)
    end
    
    -- 使用matcher模块对当前请求进行测试
    local matcher = require "core.matcher"
    local match_result = matcher.test(matchers[matcher_name])
    
    return context.response.success({
        matcher_name = matcher_name,
        match_result = match_result,
        timestamp = ngx.time(),
        note = "Testing against current request (test_data parameter no longer supported for performance)"
    })
end

-- 检查 matcher 被引用的情况
function _M.check_references(matcher_name)
    local references = {}
    
    -- 检查filter规则
    if config.configs.filter and config.configs.filter.rules then
        for i, rule in ipairs(config.configs.filter.rules) do
            if rule.matcher == matcher_name then
                table.insert(references, "filter.rules[" .. i .. "]")
            end
        end
    end
    
    -- 检查频率限制规则
    if config.configs.frequency_limit and config.configs.frequency_limit.rules then
        for i, rule in ipairs(config.configs.frequency_limit.rules) do
            if rule.matcher == matcher_name then
                table.insert(references, "frequency_limit.rules[" .. i .. "]")
            end
        end
    end
    
    -- 检查重定向规则
    if config.configs.redirect and config.configs.redirect.rules then
        for i, rule in ipairs(config.configs.redirect.rules) do
            if rule.matcher == matcher_name then
                table.insert(references, "redirect.rules[" .. i .. "]")
            end
        end
    end
    
    -- 检查协议锁定规则
    if config.configs.scheme_lock and config.configs.scheme_lock.rules then
        for i, rule in ipairs(config.configs.scheme_lock.rules) do
            if rule.matcher == matcher_name then
                table.insert(references, "scheme_lock.rules[" .. i .. "]")
            end
        end
    end
    
    -- 检查浏览器验证规则
    if config.configs.browser_verify and config.configs.browser_verify.rules then
        for i, rule in ipairs(config.configs.browser_verify.rules) do
            if rule.matcher == matcher_name then
                table.insert(references, "browser_verify.rules[" .. i .. "]")
            end
        end
    end
    
    return references
end

-- 保存配置到文件
function _M.save_config()
    return config.dump_to_file(config.configs)
end

return _M 