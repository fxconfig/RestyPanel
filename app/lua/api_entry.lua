-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : 统一API系统 - 方案1极简架构（集成路由功能）
-- @Performance: 优化初始化逻辑，避免每个请求重复初始化，提升管理API性能

local cjson = require "cjson"

local _M = {}

-- ============= 路由系统 =============
-- 路由存储
_M.routes = {}
_M.middlewares = {}
_M._initialized = false  -- 初始化标志，避免重复初始化

-- 响应工具类
local Response = {
    success = function(data, message, detail)
        return {
            code = 200,
            data = data or {},
            message = message or "Success",
            detail = detail
        }
    end,
    
    error = function(message, code, detail)
        return {
            code = code or 500,
            data = nil,
            message = message or "Internal server error",
            detail = detail
        }
    end,
    
    paginated = function(data, pagination, message)
        return {
            code = 200,
            data = {
                items = data or {},
                pagination = pagination or {}
            },
            message = message or "Success",
            detail = nil
        }
    end
}

-- 路径参数解析器
local function parse_path_params(pattern, path)
    local params = {}
    local pattern_parts = {}
    local path_parts = {}
    
    for part in string.gmatch(pattern, "([^/]+)") do
        table.insert(pattern_parts, part)
    end
    
    for part in string.gmatch(path, "([^/]+)") do
        table.insert(path_parts, part)
    end
    
    if #pattern_parts ~= #path_parts then
        return nil
    end
    
    for i, pattern_part in ipairs(pattern_parts) do
        if string.sub(pattern_part, 1, 1) == "{" and string.sub(pattern_part, -1) == "}" then
            local param_name = string.sub(pattern_part, 2, -2)
            params[param_name] = path_parts[i]
        elseif pattern_part ~= path_parts[i] then
            return nil
        end
    end
    
    return params
end

-- 路径匹配器
local function match_route(method, path)
    for _, route in ipairs(_M.routes) do
        if route.method == method then
            local params = parse_path_params(route.path, path)
            if params then
                return route, params
            end
        end
    end
    return nil, nil
end

-- 路由注册函数
function _M.register(method, path, handler, options)
    options = options or {}
    
    local route = {
        method = string.upper(method),
        path = path,
        handler = handler,
        middlewares = options.middlewares or {},
        auth = options.auth or false,
        validate = options.validate or nil,
        description = options.description or "",
        tags = options.tags or {}
    }
    
    table.insert(_M.routes, route)
    return route
end

-- RESTful 路由快捷方法
function _M.get(path, handler, options)
    return _M.register("GET", path, handler, options)
end

function _M.post(path, handler, options)
    return _M.register("POST", path, handler, options)
end

function _M.put(path, handler, options)
    return _M.register("PUT", path, handler, options)
end

function _M.delete(path, handler, options)
    return _M.register("DELETE", path, handler, options)
end

function _M.patch(path, handler, options)
    return _M.register("PATCH", path, handler, options)
end

-- 注册中间件
function _M.use(middleware)
    table.insert(_M.middlewares, middleware)
end

-- 执行中间件
local function execute_middleware(middlewares, context)
    for _, middleware in ipairs(middlewares) do
        local result = middleware(context)
        if result == false then
            return false
        end
    end
    return true
end

-- 创建请求上下文
local function create_context(route, params)
    local body_data = nil
    
    -- 如果是POST/PUT/PATCH请求，解析请求体
    local method = ngx.req.get_method()
    if method == "POST" or method == "PUT" or method == "PATCH" then
        ngx.req.read_body()
        local body_raw = ngx.req.get_body_data()
        
        if body_raw then
            -- 检查Content-Type
            local content_type = ngx.req.get_headers()["Content-Type"] or ""
            
            -- 添加调试信息
            ngx.log(ngx.INFO, "Request Content-Type: " .. content_type)
            ngx.log(ngx.INFO, "Raw body type: " .. type(body_raw))
            ngx.log(ngx.INFO, "Raw body preview: " .. string.sub(tostring(body_raw), 1, 100))
            
            -- 处理JSON类型
            if string.find(content_type, "application/json", 1, true) then
                local success, parsed_body = pcall(cjson.decode, body_raw)
                if success then
                    body_data = parsed_body
                    ngx.log(ngx.INFO, "Parsed as JSON successfully")
                else
                    ngx.log(ngx.WARN, "Failed to parse JSON body: ", body_raw)
                    body_data = {}
                end
            -- 处理文本类型（服务器配置等）
            elseif string.find(content_type, "text/plain", 1, true) or string.find(content_type, "text/html", 1, true) then
                body_data = body_raw
                ngx.log(ngx.INFO, "Using raw body for text/plain")
            -- 其他类型，尝试解析JSON，失败则返回原始内容
            else
                ngx.log(ngx.INFO, "Unknown content type, trying JSON first")
                local success, parsed_body = pcall(cjson.decode, body_raw)
                if success then
                    body_data = parsed_body
                    ngx.log(ngx.INFO, "Parsed unknown type as JSON")
                else
                    body_data = body_raw
                    ngx.log(ngx.INFO, "Using raw body for unknown type")
                end
            end
        else
            -- 检查是否有文件上传（当请求体太大时会保存到临时文件）
            local body_file = ngx.req.get_body_file()
            if body_file then
                ngx.log(ngx.INFO, "Request body saved to file: ", body_file)
                -- 读取临时文件内容
                local file = io.open(body_file, "r")
                if file then
                    local file_content = file:read("*a")
                    file:close()
                    
                    -- 根据 Content-Type 处理文件内容
                    local content_type = ngx.req.get_headers()["Content-Type"] or ""
                    if string.find(content_type, "text/plain", 1, true) then
                        body_data = file_content
                        ngx.log(ngx.INFO, "Using file content for text/plain, length: " .. #file_content)
                    elseif string.find(content_type, "application/json", 1, true) then
                        local success, parsed_body = pcall(cjson.decode, file_content)
                        if success then
                            body_data = parsed_body
                            ngx.log(ngx.INFO, "Parsed file content as JSON")
                        else
                            body_data = file_content
                            ngx.log(ngx.INFO, "Failed to parse file content as JSON, using raw content")
                        end
                    else
                        body_data = file_content
                        ngx.log(ngx.INFO, "Using raw file content for unknown type")
                    end
                else
                    ngx.log(ngx.ERR, "Failed to read body file: ", body_file)
                    body_data = {}
                end
            end
        end
    end
    
    return {
        method = method,
        uri = ngx.ctx.route_path, -- 使用 context 中的路径
        params = params or {},
        query = ngx.req.get_uri_args(),
        headers = ngx.req.get_headers(),
        body = body_data,
        user = nil, -- 认证后设置
        route = route,
        response = Response
    }
end

-- ============= API系统功能 =============

-- 初始化API系统
function _M.init()
    -- 避免重复初始化，提高性能
    if _M._initialized then
        return
    end
    
    -- 设置JSON编码配置
    cjson.encode_sparse_array(true)
    cjson.encode_empty_table_as_object(false)
    
    -- 加载统一路由模块（已移动到controllers目录）
    local success, routes = pcall(require, "controllers.routes")
    if not success then
        ngx.log(ngx.ERR, "Failed to load routes module: ", routes)
        error("Routes module loading failed")
    end
    -- 标记为已初始化
    _M._initialized = true
    
    ngx.log(ngx.INFO, "API system initialized with ", #_M.routes, " routes")
end

-- 确保API系统已初始化（高效版本）
function _M.ensure_initialized()
    if not _M._initialized then
        _M.init()
    end
end

-- 处理API请求的主入口
function _M.handle()
    -- 从URI中提取API路径
    local api_prefix = "/asd1239axasd/api"
    local uri = ngx.var.uri
    
    if string.sub(uri, 1, #api_prefix) == api_prefix then
        ngx.ctx.route_path = string.sub(uri, #api_prefix + 1)
        if ngx.ctx.route_path == "" then
            ngx.ctx.route_path = "/"
        end
    else
        ngx.ctx.route_path = uri
    end

    local success, result = pcall(_M.safe_handle)
    
    if not success then
        ngx.log(ngx.ERR, "API entry error: ", result)
        ngx.status = 200
        ngx.header.content_type = "application/json"
        ngx.say(cjson.encode({
            code = 500,
            data = nil,
            message = "Internal server error"
        }))
        ngx.exit(200)
    end
end

-- 安全的请求处理
function _M.safe_handle()
    -- 确保API系统已初始化（优化：只在未初始化时才调用）
    _M.ensure_initialized()
    
    -- 设置基本的安全头部
    ngx.header["X-Content-Type-Options"] = "nosniff"
    ngx.header["X-Frame-Options"] = "DENY"
    ngx.header["X-XSS-Protection"] = "1; mode=block"
    
    -- 请求限制检查
    local content_length = tonumber(ngx.var.content_length or "0")
    local max_body_size = 10 * 1024 * 1024  -- 10MB
    
    if content_length > max_body_size then
        ngx.status = 200
        ngx.header.content_type = "application/json"
        ngx.say(cjson.encode({
            code = 413,
            data = nil,
            message = "Request entity too large",
            detail = { max_size = max_body_size }
        }))
        return ngx.exit(200)
    end
    
    -- 处理路由请求
    _M.handle_request()
end

-- 核心请求处理
function _M.handle_request()
    local start_time = ngx.now()
    local method = ngx.req.get_method()
    local uri = ngx.ctx.route_path or "/"
    
    -- 查找匹配的路由
    local route, params = match_route(method, uri)
    
    if not route then
        ngx.status = 200
        ngx.header.content_type = "application/json"
        ngx.say(cjson.encode({
            code = 404,
            data = nil,
            message = "API endpoint not found",
            detail = {
                method = method,
                path = uri,
                available_routes = _M.get_route_list()
            }
        }))
        return ngx.exit(200)
    end
    
    -- 创建上下文
    local context = create_context(route, params)
    
    -- 设置标准响应头
    ngx.header.content_type = "application/json; charset=utf-8"
    ngx.header["X-Powered-By"] = "RestyPanel"
    ngx.header["X-Response-Time"] = "0"
    
    -- 执行全局中间件
    if not execute_middleware(_M.middlewares, context) then
        return
    end
    
    -- 执行路由中间件
    if not execute_middleware(route.middlewares, context) then
        return
    end
    
    -- 执行处理器
    local success, result = pcall(route.handler, context)
    
    if not success then
        ngx.log(ngx.ERR, "Route handler error [", route.method, " ", route.path, "]: ", result)
        ngx.status = 200
        ngx.say(cjson.encode({
            code = 500,
            data = nil,
            message = "Internal server error",
            detail = {
                route = route.path,
                method = route.method
            }
        }))
        return ngx.exit(200)
    end
    
    -- 计算响应时间并设置头部
    local response_time = (ngx.now() - start_time) * 1000
    ngx.header["X-Response-Time"] = string.format("%.2fms", response_time)
    
    -- 记录性能指标
    _M.record_metrics(route, response_time, ngx.status)
    
    -- 输出响应
    if type(result) == "table" then
        ngx.say(cjson.encode(result))
    else
        ngx.say(result or "")
    end
    
    ngx.exit(ngx.HTTP_OK)
end

-- 获取路由列表
function _M.get_route_list()
    local routes = {}
    for _, route in ipairs(_M.routes) do
        table.insert(routes, route.method .. " " .. route.path)
    end
    return routes
end

-- 记录性能指标
function _M.record_metrics(route, response_time, status_code)
    local stats = ngx.shared.dashboard_cache
    if stats then
        stats:incr("total_requests", 1, 0)
        
        local route_key = "response_time:" .. route.method .. ":" .. route.path
        stats:set(route_key, response_time, 300)
        
        local status_key = "status:" .. tostring(status_code)
        stats:incr(status_key, 1, 0)
        
        local api_key = "api_calls:" .. route.path
        stats:incr(api_key, 1, 0)
    end
end

-- 生成路由文档
function _M.generate_docs()
    local docs = {
        version = "1.0.0",
        title = "RestyPanel API Documentation",
        routes = {}
    }
    
    for _, route in ipairs(_M.routes) do
        table.insert(docs.routes, {
            method = route.method,
            path = route.path,
            description = route.description,
            auth_required = route.auth,
            tags = route.tags
        })
    end
    
    return docs
end



return _M 