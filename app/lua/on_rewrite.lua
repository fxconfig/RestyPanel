local config = require "core.config"
local uri_rewrite = require "services.uri_rewrite"
local redirect = require "services.redirect"
local scheme_lock = require "services.scheme_lock"

if ngx.var.vn_exec_flag and ngx.var.vn_exec_flag ~= '' then
    return
end

-- 更新配置
config.update_config()

-- 基于配置的 base_uri "去壳"，统一后续 URI 处理。
do
    local cfg = config.get_configs()
    local base_uri = cfg.base_uri or ""
    if base_uri ~= "" then
        -- 去掉尾部 /api，得到管理后台前缀，如 /asd1239axasd
        local prefix = base_uri:gsub("/api$", "")
        if prefix ~= "" and ngx.var.uri:sub(1, #prefix) == prefix then
            local new = ngx.var.uri:sub(#prefix + 1)
            if new == "" then new = "/" end
            ngx.req.set_uri(new, false)
        end
    end
end

uri_rewrite.filter()
redirect.filter()
scheme_lock.filter()
