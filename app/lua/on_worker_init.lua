local cjson = require "cjson"
local hc = require "resty.upstream.healthcheck"

-- 已无需设置 $base_uri 变量

-- 读取配置文件
local function load_upstream_config()
    local config_file = "/app/configs/upstream_config.json"
    local file = io.open(config_file, "r")
    if not file then
        ngx.log(ngx.ERR, "failed to open upstream config file: " .. config_file)
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, config = pcall(cjson.decode, content)
    if not success then
        ngx.log(ngx.ERR, "failed to decode upstream config JSON: " .. config)
        return nil
    end
    
    return config
end

-- 为配置了健康检查的upstream设置spawn_checker
local function setup_health_checks(config)
    if not config or not config.upstreams then
        ngx.log(ngx.INFO, "no upstream configuration found, skipping health checks")
        return
    end
    
    for upstream_name, upstream_config in pairs(config.upstreams) do
        -- 仅对启用的 upstream 且含有至少一个启用 server 进行健康检查
        if upstream_config.enable == false then
            ngx.log(ngx.INFO, "upstream " .. upstream_name .. " is disabled, skip health check")
        else
            -- 判断 server 列表中是否有启用的 server
            local has_enabled_server = false
            if upstream_config.servers then
                for _, s in ipairs(upstream_config.servers) do
                    local enabled = true
                    if type(s) == "table" and s.enable == false then
                        enabled = false
                    end
                    if enabled then
                        has_enabled_server = true
                        break
                    end
                end
            end

            if not has_enabled_server then
                ngx.log(ngx.INFO, "no enabled server in upstream " .. upstream_name .. ", skip health check")
            else
                local hc_config = upstream_config.health_check
                if hc_config and (hc_config.enabled == nil or hc_config.enabled) then
                    ngx.log(ngx.INFO, "setting up health check for upstream: " .. upstream_name)
                    local ok, err = hc.spawn_checker({
                        shm = "healthcheck",
                        upstream = upstream_name,
                        type = hc_config.type or "http",
                        http_req = hc_config.http_req or "GET /health HTTP/1.0\r\nHost: backend\r\n\r\n",
                        interval = hc_config.interval or 6000,
                        timeout = hc_config.timeout or 3000,
                        fall = hc_config.fall or 1,
                        rise = hc_config.rise or 1,
                        valid_statuses = hc_config.valid_statuses or {200},
                        concurrency = hc_config.concurrency or 1,
                    })
                    if not ok then
                        ngx.log(ngx.ERR, "failed to spawn health checker for " .. upstream_name .. ": " .. (err or "unknown error"))
                    else
                        ngx.log(ngx.INFO, "health checker started for upstream: " .. upstream_name)
                    end
                else
                    ngx.log(ngx.INFO, "health check not enabled for upstream: " .. upstream_name .. ", skipping")
                end
            end
        end
    end
end

-- 加载配置并设置健康检查
local config = load_upstream_config()
if config then
    setup_health_checks(config)
else
    ngx.log(ngx.INFO, "no configuration file found, health checks disabled")
end

-- 预初始化API系统，避免首次请求时的初始化开销
local function preload_api_system()
    local success, api_entry = pcall(require, "api_entry")
    if success and api_entry.init then
        pcall(api_entry.init)
        ngx.log(ngx.INFO, "API system pre-initialized in worker")
    else
        ngx.log(ngx.INFO, "API system not available for pre-initialization")
    end
end

-- 预加载API系统
preload_api_system()

local _M = {}

function _M.run()
    local status = require "services.status"
    -- 重设状态计数
    status.reset()
    
    -- 确保报告目录存在
    local config = require "core.config"
    local reports_dir = config.get_configs().admin.paths.reports_dir or "/app/web/reports/"
    local cmd = "mkdir -p " .. reports_dir .. " && chmod -R 777 " .. reports_dir
    os.execute(cmd)
    
    -- 可以做一些初始化工作，如检查配置文件存在，重置一些值等
    -- 该函数在worker进程启动时运行
    ngx.log(ngx.INFO, "worker initialized at " .. ngx.http_time(ngx.time()))
end

return _M