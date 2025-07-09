-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Response Template Configuration Controller

local cjson = require "cjson"
local config = require "core.config"

local _M = {}

-- 获取所有response模板
function _M.list(context)
    local responses = config.configs.response or {}
    
    local response_list = {}
    for name, response_config in pairs(responses) do
        table.insert(response_list, {
            name = name,
            content_type = response_config.content_type,
            body = response_config.body,
            headers = response_config.headers or {},
            status_code = response_config.status_code or 200,
            created_at = response_config.created_at or 0,
            updated_at = response_config.updated_at or 0
        })
    end
    
    -- 支持搜索和分页
    local search = context.query.search or ""
    local page = tonumber(context.query.page) or 1
    local limit = tonumber(context.query.limit) or 20
    
    if search ~= "" then
        local filtered = {}
        for _, response in ipairs(response_list) do
            if string.find(response.name, search, 1, true) or 
               string.find(response.content_type or "", search, 1, true) then
                table.insert(filtered, response)
            end
        end
        response_list = filtered
    end
    
    local total = #response_list
    local start_idx = (page - 1) * limit + 1
    local end_idx = math.min(start_idx + limit - 1, total)
    
    local paginated_list = {}
    for i = start_idx, end_idx do
        table.insert(paginated_list, response_list[i])
    end
    
    local pagination = {
        page = page,
        limit = limit,
        total = total,
        pages = math.ceil(total / limit)
    }
    
    return context.response.paginated(paginated_list, pagination)
end

-- 获取单个response模板
function _M.get(context)
    local response_name = context.params.name
    local responses = config.configs.response or {}
    
    if not responses[response_name] then
        return context.response.error("Response template not found", 404)
    end
    
    local response_data = {
        name = response_name,
        config = responses[response_name]
    }
    
    return context.response.success(response_data)
end

-- 创建新的response模板
function _M.create(context)
    local data = context.body
    local response_name = data.name
    
    if not response_name then
        return context.response.error("Response name is required", 400)
    end
    
    if not data.content_type then
        return context.response.error("Content type is required", 400)
    end
    
    if not data.body then
        return context.response.error("Response body is required", 400)
    end
    
    -- 确保response配置结构存在
    if not config.configs.response then
        config.configs.response = {}
    end
    
    local responses = config.configs.response
    
    if responses[response_name] then
        return context.response.error("Response template already exists", 409)
    end
    
    local response_config = {
        content_type = data.content_type,
        body = data.body,
        headers = data.headers or {},
        status_code = data.status_code or 200,
        created_at = ngx.time(),
        updated_at = ngx.time(),
        created_by = context.user and context.user.id or "system"
    }
    
    config.configs.response[response_name] = response_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. (err or "unknown error"), 500)
    end
    
    return context.response.success({
        name = response_name,
        config = response_config
    }, "Response template created successfully", 201)
end

-- 更新response模板
function _M.update(context)
    local response_name = context.params.name
    local data = context.body
    local responses = config.configs.response or {}
    
    if not responses[response_name] then
        return context.response.error("Response template not found", 404)
    end
    
    local existing = responses[response_name]
    local updated_config = {
        content_type = data.content_type or existing.content_type,
        body = data.body or existing.body,
        headers = data.headers or existing.headers or {},
        status_code = data.status_code or existing.status_code or 200,
        created_at = existing.created_at,
        created_by = existing.created_by,
        updated_at = ngx.time(),
        updated_by = context.user and context.user.id or "system"
    }
    
    config.configs.response[response_name] = updated_config
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({
        name = response_name,
        config = updated_config
    }, "Response template updated successfully")
end

-- 删除response模板
function _M.delete(context)
    local response_name = context.params.name
    local responses = config.configs.response or {}
    
    if not responses[response_name] then
        return context.response.error("Response template not found", 404)
    end
    
    -- 检查是否被filter规则引用
    local references = _M.check_references(response_name)
    if #references > 0 then
        return context.response.error("Cannot delete response template: it is referenced by " .. table.concat(references, ", "), 400)
    end
    
    config.configs.response[response_name] = nil
    
    -- 保存配置
    local success, err = _M.save_config()
    if not success then
        return context.response.error("Failed to save configuration: " .. err, 500)
    end
    
    return context.response.success({}, "Response template deleted successfully")
end

-- 预览response模板效果
function _M.preview(context)
    local response_name = context.params.name
    local responses = config.configs.response or {}
    
    if not responses[response_name] then
        return context.response.error("Response template not found", 404)
    end
    
    local template = responses[response_name]
    
    -- 设置响应头
    ngx.header.content_type = template.content_type
    if template.headers then
        for key, value in pairs(template.headers) do
            ngx.header[key] = value
        end
    end
    
    -- 设置状态码
    ngx.status = template.status_code or 200
    
    -- 输出响应体
    ngx.say(template.body)
    ngx.exit(ngx.HTTP_OK)
end

-- 检查response模板被引用的情况
function _M.check_references(response_name)
    local references = {}
    
    -- 检查filter规则
    if config.configs.filter and config.configs.filter.rules then
        for i, rule in ipairs(config.configs.filter.rules) do
            if rule.response == response_name then
                table.insert(references, "filter.rules[" .. i .. "]")
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