-- -*- coding: utf-8 -*-
-- @Date    : 2016-01-07 15:15
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    :
-- @Disc    : redirect request to right scheme

local matcher = require "core.matcher"
local config = require "core.config"

local _M = {}

function _M.filter()
    if config.configs.scheme_lock.enable ~= true then
        return
    end

    local matcher_list = config.configs['matcher']
    for i, rule in ipairs( config.configs.scheme_lock.rules ) do
        local enable = rule['enable']
        local matcher_config = matcher_list[ rule['matcher'] ] 
        if enable == true and matcher.test( matcher_config ) == true then
            if rule['to_scheme'] == 'https' and ngx.var.scheme == 'http' then
                ngx.redirect("https://" .. ngx.var.host .. ngx.var.request_uri, 301)
            elseif rule['to_scheme'] == 'http' and ngx.var.scheme == 'https' then
                ngx.redirect("http://" .. ngx.var.host .. ngx.var.request_uri, 301)
            end
            return
        end
    end
end

return _M
