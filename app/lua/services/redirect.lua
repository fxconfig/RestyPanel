-- -*- coding: utf-8 -*-
-- @Date    : 2016-01-02 20:39
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : redirect path

local matcher = require "core.matcher"
local config = require "core.config"

local _M = {}

function _M.filter()
    if config.configs.redirect.enable ~= true then
        return
    end

    local ctx = ngx.ctx
    ctx.tag = "V_REDIRECT"

    local vn_redirect_to_uri = nil
    local ngx_redirect = ngx.redirect
    local matcher_list = config.configs['matcher']

    local new_url = nil 
    local re_gsub = ngx.re.gsub
    local ngx_var = ngx.var 
    local ngx_var_uri = ngx_var.uri
    local ngx_var_scheme = ngx_var.scheme
    local ngx_var_host = ngx_var.host

    for i, rule in ipairs( config.configs.redirect.rules ) do
        local enable = rule['enable']
        local matcher_config = matcher_list[ rule['matcher'] ] 
        if enable == true and matcher.test( matcher_config ) == true then
            replace_re = rule['replace_re']
            if replace_re ~= nil and string.len( replace_re ) > 0  then
                new_url = re_gsub( ngx_var_uri, replace_re, rule['to_uri'] ) 
            else
                new_url = rule['to_uri']
            end

            if new_url ~= ngx_var_uri then

                if string.find( new_url, 'http') ~= 1 then
                    new_url = ngx_var_scheme.."://"..ngx_var_host..new_url
                end

                if ngx_var.args ~= nil then
                    ngx_redirect( new_url.."?"..ngx_var.args , ngx.HTTP_MOVED_TEMPORARILY)
                else
                    ngx_redirect( new_url , ngx.HTTP_MOVED_TEMPORARILY)
                end
            end
            return
        end
    end
end

return _M
