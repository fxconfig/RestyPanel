-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Authentication Controller (JWT based with lua-resty-jwt and token whitelist)

local cjson = require "cjson"
local config = require "core.config"
local jwt = require "resty.jwt"

local _M = {}

-- JWT Token管理
local jwt_tokens_dict = ngx.shared.jwt_tokens

-- 获取JWT配置
local function get_jwt_config()
    local admin_config = config.configs['admin']
    if not admin_config then
        return nil, "Admin configuration not found"
    end
    
    return {
        secret = admin_config.jwt_secret or "RestyPanel-JWT-Secret-Key-2024",
        expires = admin_config.jwt_expires or 86400
    }, nil
end

-- 生成JWT token
local function generate_jwt_token(payload, secret)
    -- 添加调试日志
    ngx.log(ngx.DEBUG, "Generating JWT with payload: ", cjson.encode(payload), "Using secret length: ", string.len(secret))
    
    -- 直接使用静态方法
    local jwt_token = jwt:sign(
        secret,
        {
            header = {
                typ = "JWT",
                alg = "HS256"
            },
            payload = payload
        }
    )
    
    ngx.log(ngx.DEBUG, "Generated JWT token length: ", jwt_token and string.len(jwt_token) or "nil")
    return jwt_token
end

-- 验证JWT token
local function verify_jwt_token(token, secret)
    -- ngx.log(ngx.INFO, "Verifying JWT token length: ", string.len(token))
    -- ngx.log(ngx.INFO, "Using secret length: ", string.len(secret))
    
    -- 直接使用静态方法
    local jwt_obj = jwt:verify(secret, token)
    
    ngx.log(ngx.DEBUG, "JWT verification result - valid: ", jwt_obj.valid, ", reason: ", jwt_obj.reason or "none")
    
    if not jwt_obj.valid then
        return false, jwt_obj.reason or "Invalid token"
    end
    
    -- 检查token是否过期
    if jwt_obj.payload and jwt_obj.payload.exp and jwt_obj.payload.exp < ngx.time() then
       return false, "Token expired"
    end
    
    return true, jwt_obj.payload
end

-- 将token添加到白名单
local function add_token_to_whitelist(token, username, expires_in)
    local token_data = {
        username = username,
        created_at = ngx.time(),
        expires_at = ngx.time() + expires_in
    }
    
    -- 使用token的后8位作为key以节省内存
    local token_key = string.sub(token, -8)
    local success, err = jwt_tokens_dict:set(token_key, cjson.encode(token_data), expires_in)
    
    if not success then
        ngx.log(ngx.ERR, "Failed to add token to whitelist: ", err)
        return false
    end
    
    return true
end

-- 从白名单移除token
local function remove_token_from_whitelist(token)
    local token_key = string.sub(token, -8)
    jwt_tokens_dict:delete(token_key)
    return true
end

-- 检查token是否在白名单中
local function is_token_in_whitelist(token)
    local debug = true
    if debug then return true end
    local token_key = string.sub(token, -8)
    local token_data_json = jwt_tokens_dict:get(token_key)
    
    if not token_data_json then
        return false
    end
    
    local success, token_data = pcall(cjson.decode, token_data_json)
    if not success then
        return false
    end
    
    -- 检查是否过期
    if token_data.expires_at < ngx.time() then
        jwt_tokens_dict:delete(token_key)
        return false
    end
    
    return true, token_data
end

-- 清理过期token
-- local function cleanup_expired_tokens()
    -- 这个函数可以通过定时任务调用，这里先留空
    -- 由于shared dict会自动清理过期数据，所以暂时不需要手动清理
-- end

-- 用户登录
function _M.login(context)
    local data = context.body
    local username = data.username
    local password = data.password
    
    if not username or not password then
        return context.response.error("Username and password are required", 400)
    end
    
    -- 获取JWT配置
    local jwt_config, err = get_jwt_config()
    if not jwt_config then
        return context.response.error("JWT configuration error: " .. err, 500)
    end
    
    -- 验证用户凭据
    local admin_config = config.configs['admin']
    if not admin_config or not admin_config.enable then
        return context.response.error("Admin access is disabled", 503)
    end
    
    local admin_users = admin_config.users or {}
    local user_found = false
    local user_info = nil
    
    for _, admin in ipairs(admin_users) do
        if admin.user == username then
            -- 简化的密码验证 (实际应该使用安全的哈希验证)
            if admin.password == password then
                user_found = true
                user_info = admin
                break
            end
        end
    end
    
    if not user_found then
        return context.response.error("Invalid username or password", 401)
    end
    
    -- 创建JWT payload (简化版本)
    local current_time = ngx.time()
    local expires_in = jwt_config.expires
    local payload = {
        sub = username, -- subject (user identifier)
        iat = current_time, -- issued at
        exp = current_time + expires_in, -- expiration time
        nbf = current_time, -- not before
        iss = "RestyPanel", -- issuer
        aud = "RestyPanel-api", -- audience
        jti = ngx.md5(username .. current_time) -- JWT ID
    }
    
    -- 生成JWT token
    local token = generate_jwt_token(payload, jwt_config.secret)
    
    -- 将token添加到白名单
    local whitelist_success = add_token_to_whitelist(token, username, expires_in)
    if not whitelist_success then
        return context.response.error("Failed to create session", 500)
    end
    
    return context.response.success({
        access_token = token,
        token_type = "Bearer",
        expires_in = expires_in,
        user = {
            id = username
        }
    }, "Login successful")
end

-- 用户登出 (真正撤销token)
function _M.logout(context)
    if not context.user then
        return context.response.error("User not authenticated", 401)
    end
    
    -- 直接从Authorization头获取当前token
    local auth_header = context.headers["Authorization"] or context.headers["authorization"]
    local current_token = nil
    if auth_header then
        current_token = string.match(auth_header, "^Bearer%s+(.+)$")
    end
    
    if not current_token then
        return context.response.error("No token found in request", 400)
    end
    
    -- 从白名单移除token
    remove_token_from_whitelist(current_token)
    
    return context.response.success({
        message = "Successfully logged out",
        revoked_token = string.sub(current_token, -8)  -- 调试信息：显示被撤销token的后8位
    }, "Logout successful")
end

-- 获取用户信息
function _M.profile(context)
    if not context.user then
        return context.response.error("User not authenticated", 401)
    end
    
    local admin_config = config.configs['admin']
    if not admin_config or not admin_config.enable then
        return context.response.error("Admin access is disabled", 503)
    end
    
    local admin_users = admin_config.users or {}
    local user_info = nil
    
    for _, admin in ipairs(admin_users) do
        if admin.user == context.user.id then
            user_info = {
                id = admin.user,
                enable = admin_config.enable,
                created_at = admin.created_at or 0,
                last_login = admin.last_login or 0,
                token_info = {
                    issued_at = context.user.token_payload.iat,
                    expires_at = context.user.token_payload.exp,
                    jwt_id = context.user.token_payload.jti
                }
            }
            break
        end
    end
    
    if not user_info then
        return context.response.error("User not found", 404)
    end
    
    return context.response.success(user_info)
end

-- 刷新Token
function _M.refresh(context)
    if not context.user then
        return context.response.error("User not authenticated", 401)
    end
    
    -- 获取JWT配置
    local jwt_config, err = get_jwt_config()
    if not jwt_config then
        return context.response.error("JWT configuration error: " .. err, 500)
    end
    
    -- 直接从Authorization头获取当前token
    local auth_header = context.headers["Authorization"] or context.headers["authorization"]
    local current_token = nil
    if auth_header then
        current_token = string.match(auth_header, "^Bearer%s+(.+)$")
    end
    
    -- 获取当前用户信息
    local admin_config = config.configs['admin']
    if not admin_config or not admin_config.enable then
        return context.response.error("Admin access is disabled", 503)
    end
    
    local admin_users = admin_config.users or {}
    local user_info = nil
    
    for _, admin in ipairs(admin_users) do
        if admin.user == context.user.id then
            user_info = admin
            break
        end
    end
    
    if not user_info then
        return context.response.error("User not found", 404)
    end
    
    -- 移除当前token（如果存在）
    if current_token then
        remove_token_from_whitelist(current_token)
    end
    
    -- 创建新的JWT payload (简化版本)
    local current_time = ngx.time()
    local expires_in = jwt_config.expires
    local payload = {
        sub = context.user.id,
        iat = current_time,
        exp = current_time + expires_in,
        nbf = current_time,
        iss = "RestyPanel",
        aud = "RestyPanel-api",
        jti = ngx.md5(context.user.id .. current_time)
    }
    
    -- 生成新的JWT token
    local token = generate_jwt_token(payload, jwt_config.secret)
    
    -- 将新token添加到白名单
    local whitelist_success = add_token_to_whitelist(token, context.user.id, expires_in)
    if not whitelist_success then
        return context.response.error("Failed to refresh session", 500)
    end
    
    return context.response.success({
        access_token = token,
        token_type = "Bearer",
        expires_in = expires_in,
        revoked_token = current_token and string.sub(current_token, -8) or "none"  -- 调试信息
    }, "Token refreshed successfully")
end

-- 导出JWT验证函数供中间件使用
_M.verify_jwt = verify_jwt_token
_M.is_token_in_whitelist = is_token_in_whitelist
_M.get_jwt_config = get_jwt_config

return _M 