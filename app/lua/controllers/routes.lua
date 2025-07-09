-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01  
-- @Author  : RestyPanel Team
-- @Disc    : 简化路由配置 - 只保留基本 CRUD 操作

local router = require "api_entry"

-- ============= 中间件导入 =============
local middleware = require "core.middleware"

-- 配置JWT认证中间件，跳过登录和健康检查等公开端点
local jwt_auth = middleware.jwt_auth({
    skip_paths = {"/auth/login", "/health", "/ws/.*"}  -- 重新跳过 WebSocket 路径的认证
})

-- 重新启用JWT认证中间件
router.use(jwt_auth)

-- ============= 控制器导入 =============
local auth_controller = require "controllers.auth_controller"
local upstream_controller = require "controllers.upstream_controller"
local server_controller = require "controllers.server_controller"
local matcher_controller = require "controllers.matcher_controller"
local response_controller = require "controllers.response_controller"
local filter_controller = require "controllers.filter_controller"  -- 使用新版本（已重命名）
local frequency_limit_controller = require "controllers.frequency_limit_controller"
local redirect_controller = require "controllers.redirect_controller"
local scheme_lock_controller = require "controllers.scheme_lock_controller"
local logs_controller = require "controllers.logs_controller" -- 新增日志控制器

-- ============= 系统路由 =============
router.get("/health", function(context)
    return context.response.success({
        status = "healthy",
        timestamp = ngx.time(),
        version = "2.0.0"
    })
end)

-- ============= 认证路由 =============
router.post("/auth/login", auth_controller.login)
router.post("/auth/logout", auth_controller.logout)
router.get("/auth/profile", auth_controller.profile)
router.post("/auth/refresh", auth_controller.refresh)

-- ============= Upstream 管理 CRUD =============
router.get("/upstreams", upstream_controller.list)
router.get("/upstreams/{name}", upstream_controller.get)
router.post("/upstreams", upstream_controller.create)
router.put("/upstreams/{name}", upstream_controller.update)
router.delete("/upstreams/{name}", upstream_controller.delete)
router.get("/upstream/status", upstream_controller.status)
router.get("/upstream/showconf", upstream_controller.showconf)

-- ============= Server 管理 CRUD =============
router.get("/servers", server_controller.list)
router.get("/servers/{name}", server_controller.get)
router.post("/servers/{name}", server_controller.create)
router.put("/servers/{name}", server_controller.update)
router.delete("/servers/{name}", server_controller.delete)
router.post("/servers/{name}/action", server_controller.action)

-- ============= 路径设置 =============
router.get("/admin/settings/paths", server_controller.get_path_settings)
router.put("/admin/settings/paths", server_controller.update_path_settings)

-- ============= 日志分析路由 =============
-- 日志相关路由
router.get("/logs", logs_controller.get_logs)
router.get("/logs/{filename}", logs_controller.get_log_content)
router.post("/logs/{filename}/analyze", logs_controller.analyze_log)
router.get("/log/reports", logs_controller.get_reports)
router.delete("/log/reports/{report_name}", logs_controller.delete_report)
router.delete("/log/reports", logs_controller.delete_all_reports)

-- Shell执行API
router.post("/shell/exec", function(context)
    local command = context.body.command
    if not command then
        return context.response.error("Missing command parameter", 400)
    end
    
    -- 执行shell命令
    local ok, stdout, stderr = os.execute(command)
    
    if not ok then
        return context.response.error("Command execution failed: " .. (stderr or "unknown error"), 500)
    end
    
    return context.response.success({
        stdout = stdout,
        stderr = stderr
    })
end)

-- 注意：WebSocket 代理路由已移除
-- 现在使用 Nginx 的原生 WebSocket 支持在 dashboard.conf 中处理

-- ============= Matcher CRUD =============
router.get("/matchers", matcher_controller.list)
router.get("/matchers/{name}", matcher_controller.get)
router.post("/matchers", matcher_controller.create)
router.put("/matchers/{name}", matcher_controller.update)
router.delete("/matchers/{name}", matcher_controller.delete)
router.post("/matchers/{name}/test", matcher_controller.test)

-- ============= Response CRUD =============
router.get("/responses", response_controller.list)
router.get("/responses/{name}", response_controller.get)
router.post("/responses", response_controller.create)
router.put("/responses/{name}", response_controller.update)
router.delete("/responses/{name}", response_controller.delete)

-- ============= Filter CRUD =============
router.get("/filters", filter_controller.list)
router.get("/filters/{id}", filter_controller.get)
router.post("/filters", filter_controller.create)
router.put("/filters/{id}", filter_controller.update)
router.delete("/filters/{id}", filter_controller.delete)
router.post("/filters/{id}/toggle", filter_controller.toggle)
router.post("/filters/toggle", filter_controller.toggle_filter)

-- ============= Frequency Limit CRUD =============
router.get("/frequency-limits", frequency_limit_controller.list)
router.get("/frequency-limits/{id}", frequency_limit_controller.get)
router.post("/frequency-limits", frequency_limit_controller.create)
router.put("/frequency-limits/{id}", frequency_limit_controller.update)
router.delete("/frequency-limits/{id}", frequency_limit_controller.delete)
router.post("/frequency-limits/{id}/toggle", frequency_limit_controller.toggle)
router.post("/frequency-limits/toggle", frequency_limit_controller.toggle_global)

-- ============= Redirect CRUD =============
router.get("/redirects", redirect_controller.list)
router.get("/redirects/{id}", redirect_controller.get)
router.post("/redirects", redirect_controller.create)
router.put("/redirects/{id}", redirect_controller.update)
router.delete("/redirects/{id}", redirect_controller.delete)
router.post("/redirects/{id}/toggle", redirect_controller.toggle)
router.post("/redirects/toggle", redirect_controller.toggle_global)

-- ============= Scheme Lock CRUD =============
router.get("/scheme-locks", scheme_lock_controller.list)
router.get("/scheme-locks/{id}", scheme_lock_controller.get)
router.post("/scheme-locks", scheme_lock_controller.create)
router.put("/scheme-locks/{id}", scheme_lock_controller.update)
router.delete("/scheme-locks/{id}", scheme_lock_controller.delete)
router.post("/scheme-locks/{id}/toggle", scheme_lock_controller.toggle)
router.post("/scheme-locks/toggle", scheme_lock_controller.toggle_global)

-- ============= 基本监控路由 =============
router.get("/status", function(context)
    local status = require "services.status"
    return context.response.success(status.report())
end)

router.get("/summary", function(context)
    local summary = require "services.summary"
    return context.response.success(summary.report())
end)

-- 测试API响应格式
router.get("/test", function()
    local cmd = "/usr/local/openresty/bin/openresty -t 2>/dev/null || true"
    local handle = io.popen(cmd)
    if not handle then
        return "failed"
    end
    local output = handle:read("*a")
    handle:close()
    return output
end)

-- 测试nginx配置
router.get("/test/nginx", function()
    local ret , err = os.execute("/usr/local/openresty/bin/openresty -s reload")
    if ret == 0 then
        return "success"
    else
        return "failed  " .. err
    end
end)

ngx.log(ngx.INFO, "Simplified routes registered: ", #router.routes, " endpoints with JWT auth enabled")

return router 