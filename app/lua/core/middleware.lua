-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Middleware System for RestyPanel

local cjson = require "cjson"

local _M = {}

-- 响应工具
local function error_response(message, code, detail)
    return {
        code = code or 500,
        data = nil,
        message = message,
        detail = detail
    }
end

-- CORS 中间件
function _M.cors(options)
    options = options or {}
    local allowed_origins = options.origins or {"*"}
    local allowed_methods = options.methods or {"GET", "POST", "PUT", "DELETE", "OPTIONS"}
    local allowed_headers = options.headers or {"Content-Type", "Authorization", "X-Requested-With"}
    local allow_credentials = options.credentials or false
    
    return function(context)
        local origin = context.headers["Origin"]
        
        -- 设置 CORS 头
        if origin and (allowed_origins[1] == "*" or table.contains(allowed_origins, origin)) then
            ngx.header["Access-Control-Allow-Origin"] = origin
        elseif allowed_origins[1] == "*" then
            ngx.header["Access-Control-Allow-Origin"] = "*"
        end
        
        ngx.header["Access-Control-Allow-Methods"] = table.concat(allowed_methods, ", ")
        ngx.header["Access-Control-Allow-Headers"] = table.concat(allowed_headers, ", ")
        
        if allow_credentials then
            ngx.header["Access-Control-Allow-Credentials"] = "true"
        end
        
        -- 处理预检请求
        if context.method == "OPTIONS" then
            ngx.status = 204
            ngx.exit(204)
            return false
        end
        
        return true
    end
end

-- Session 认证中间件 (JWT Based with whitelist)
function _M.session_auth(options)
    options = options or {}
    local skip_paths = options.skip_paths or {}
    
    return function(context)
        -- 添加调试日志
        ngx.log(ngx.DEBUG, "JWT Auth middleware - checking path: ", context.uri)
        
        -- 检查是否跳过认证
        for _, path in ipairs(skip_paths) do
            -- 支持多种匹配方式：完整匹配、尾匹配、包含匹配
            if context.uri == path or 
               string.match(context.uri, path .. "$") or 
               string.find(context.uri, path, 1, true) then
                ngx.log(ngx.INFO, "JWT Auth middleware - skipping path: ", context.uri, " matched: ", path)
                return true
            end
        end
        
        ngx.log(ngx.DEBUG, "JWT Auth middleware - authenticating path: ", context.uri)
        
        -- 获取Authorization头
        local auth_header = context.headers["Authorization"] or context.headers["authorization"]
        if not auth_header then
            ngx.log(ngx.WARN, "JWT Auth middleware - missing Authorization header")
            ngx.status = 401
            ngx.say(cjson.encode(error_response("Authorization header missing", 401)))
            ngx.exit(401)
            return false
        end
        
        -- 检查Bearer token格式
        local token = string.match(auth_header, "^Bearer%s+(.+)$")
        if not token then
            ngx.log(ngx.WARN, "JWT Auth middleware - invalid token format")
            ngx.status = 401
            ngx.say(cjson.encode(error_response("Invalid authorization format. Use 'Bearer <token>'", 401)))
            ngx.exit(401)
            return false
        end
        
        ngx.log(ngx.INFO, "JWT Auth middleware - validating token length: ", string.len(token))
        
        -- 验证JWT token
        local auth_controller = require "controllers.auth_controller"
        local jwt_config, config_err = auth_controller.get_jwt_config()
        
        if not jwt_config then
            ngx.log(ngx.ERR, "JWT Auth middleware - config error: ", config_err)
            ngx.status = 500
            ngx.say(cjson.encode(error_response("JWT configuration error: " .. config_err, 500)))
            ngx.exit(500)
            return false
        end
        
        local valid, payload_or_error = auth_controller.verify_jwt(token, jwt_config.secret)
        
        if not valid then
            ngx.log(ngx.WARN, "JWT Auth middleware - token validation failed: ", payload_or_error)
            ngx.status = 401
            ngx.say(cjson.encode(error_response("Invalid token: " .. payload_or_error, 401)))
            ngx.exit(401)
            return false
        end
        
        -- 检查token是否在白名单中
        local in_whitelist, whitelist_data = auth_controller.is_token_in_whitelist(token)
        if not in_whitelist then
            ngx.log(ngx.WARN, "JWT Auth middleware - token not in whitelist")
            ngx.status = 401
            ngx.say(cjson.encode(error_response("Token has been revoked or expired", 401)))
            ngx.exit(401)
            return false
        end
        
        -- 验证用户是否仍然有效
        local config = require "core.config"
        local admin_config = config.configs['admin']
        if not admin_config or not admin_config.enable then
            ngx.log(ngx.WARN, "JWT Auth middleware - admin access disabled")
            ngx.status = 401
            ngx.say(cjson.encode(error_response("Admin access is disabled", 401)))
            ngx.exit(401)
            return false
        end
        
        local admin_users = admin_config.users or {}
        local user_found = false
        
        for _, admin in ipairs(admin_users) do
            if admin.user == payload_or_error.sub then
                context.user = {
                    id = admin.user,
                    token_payload = payload_or_error,
                    token = token  -- 存储原始token供logout使用
                }
                user_found = true
                ngx.log(ngx.INFO, "JWT Auth middleware - user authenticated: ", admin.user)
                break
            end
        end
        
        if not user_found then
            ngx.log(ngx.WARN, "JWT Auth middleware - user not found: ", payload_or_error.sub)
            ngx.status = 401
            ngx.say(cjson.encode(error_response("User not found or disabled", 401)))
            ngx.exit(401)
            return false
        end
        
        return true
    end
end

-- JWT 认证中间件（别名，为了API命名一致性）
function _M.jwt_auth(options)
    return _M.session_auth(options)
end

-- 参数验证中间件
function _M.validate(schema)
    return function(context)
        -- 获取请求体
        if context.body == nil then
            ngx.req.read_body()
            local body_data = ngx.req.get_body_data()
            if body_data then
                local success, parsed = pcall(cjson.decode, body_data)
                context.body = success and parsed or {}
            else
                context.body = {}
            end
        end
        
        -- 验证参数
        local errors = {}
        
        if schema.required then
            for _, field in ipairs(schema.required) do
                if not context.body[field] and not context.query[field] and not context.params[field] then
                    table.insert(errors, "Field '" .. field .. "' is required")
                end
            end
        end
        
        if schema.fields then
            for field, rules in pairs(schema.fields) do
                local value = context.body[field] or context.query[field] or context.params[field]
                
                if value then
                    -- 类型验证
                    if rules.type and type(value) ~= rules.type then
                        table.insert(errors, "Field '" .. field .. "' must be of type " .. rules.type)
                    end
                    
                    -- 长度验证
                    if rules.min_length and string.len(tostring(value)) < rules.min_length then
                        table.insert(errors, "Field '" .. field .. "' must be at least " .. rules.min_length .. " characters")
                    end
                    
                    if rules.max_length and string.len(tostring(value)) > rules.max_length then
                        table.insert(errors, "Field '" .. field .. "' must not exceed " .. rules.max_length .. " characters")
                    end
                    
                    -- 正则验证
                    if rules.pattern and not string.match(tostring(value), rules.pattern) then
                        table.insert(errors, "Field '" .. field .. "' format is invalid")
                    end
                end
            end
        end
        
        if #errors > 0 then
            ngx.status = 400
            ngx.say(cjson.encode(error_response("Validation failed", 400, {errors = errors})))
            ngx.exit(400)
            return false
        end
        
        return true
    end
end

-- 限流中间件
function _M.rate_limit(options)
    options = options or {}
    local limit = options.limit or 100  -- 每分钟请求数
    local window = options.window or 60  -- 时间窗口(秒)
    local key_func = options.key_func or function(context)
        return "rate_limit:" .. (context.user and context.user.id or ngx.var.remote_addr)
    end
    
    return function(context)
        local key = key_func(context)
        local current_time = ngx.time()
        local window_start = current_time - (current_time % window)
        local window_key = key .. ":" .. window_start
        
        local current_count = ngx.shared.frequency_limit:get(window_key) or 0
        
        if current_count >= limit then
            ngx.status = 429
            ngx.header["X-RateLimit-Limit"] = limit
            ngx.header["X-RateLimit-Remaining"] = "0"
            ngx.header["X-RateLimit-Reset"] = window_start + window
            ngx.say(cjson.encode(error_response("Rate limit exceeded", 429)))
            ngx.exit(429)
            return false
        end
        
        -- 增加计数
        ngx.shared.frequency_limit:incr(window_key, 1, 0, window)
        
        -- 设置响应头
        ngx.header["X-RateLimit-Limit"] = limit
        ngx.header["X-RateLimit-Remaining"] = limit - current_count - 1
        ngx.header["X-RateLimit-Reset"] = window_start + window
        
        return true
    end
end

-- 日志中间件
function _M.logger(options)
    options = options or {}
    local log_level = options.level or ngx.INFO
    
    return function(context)
        local start_time = ngx.now()
        
        -- 记录请求开始
        ngx.log(log_level, string.format(
            "Request started: %s %s from %s",
            context.method,
            context.uri,
            ngx.var.remote_addr
        ))
        
        -- 在请求结束后记录（这需要在响应阶段调用）
        ngx.ctx.log_request_end = function(status_code)
            local duration = ngx.now() - start_time
            ngx.log(log_level, string.format(
                "Request completed: %s %s -> %d (%.3fs)",
                context.method,
                context.uri,
                status_code or ngx.status,
                duration
            ))
        end
        
        return true
    end
end

-- IP 白名单中间件
function _M.ip_whitelist(allowed_ips)
    allowed_ips = allowed_ips or {"127.0.0.1", "::1"}
    
    return function(context)
        local client_ip = ngx.var.remote_addr
        
        for _, allowed_ip in ipairs(allowed_ips) do
            if client_ip == allowed_ip then
                return true
            end
        end
        
        ngx.status = 403
        ngx.say(cjson.encode(error_response("Access denied", 403)))
        ngx.exit(403)
        return false
    end
end

-- 请求大小限制中间件
function _M.body_size_limit(max_size)
    max_size = max_size or 1024 * 1024  -- 1MB
    
    return function(context)
        local content_length = tonumber(context.headers["Content-Length"] or "0")
        
        if content_length > max_size then
            ngx.status = 413
            ngx.say(cjson.encode(error_response("Request entity too large", 413)))
            ngx.exit(413)
            return false
        end
        
        return true
    end
end

-- 工具函数：检查表中是否包含某个值
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

return _M 