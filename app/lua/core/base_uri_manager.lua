-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : Base URI 管理模块（静态配置版）

local _M = {}

-- 只从 config（admin.json）静态读取 base_uri
function _M.get_base_uri()
    local config = require "core.config"
    local configs = config.get_configs()
    local api_base_uri = configs.base_uri .. "/api" or "/asd1239axasd/api"
    -- 去掉 /api 后缀，只保留前端资源的 base_uri
    local frontend_base_uri = api_base_uri:gsub("/api$", "")
    return frontend_base_uri
end

function _M.get_api_base_uri()
    local config = require "core.config"
    local configs = config.get_configs()
    return  configs.base_uri .. "/api" or "/asd1239axasd/api"
end

return _M 