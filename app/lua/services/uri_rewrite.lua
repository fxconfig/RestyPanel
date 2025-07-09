-- -*- coding: utf-8 -*-
-- @Date    : 2016-02-21 
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : rewrite uri inside nginx

local matcher = require "core.matcher"
local config = require "core.config"

local _M = {}

function _M.filter()
    if config.configs.uri_rewrite.enable ~= true then
        return
    end

    local ctx = ngx.ctx
    ctx.tag = "V_URI_REWRITE"

    local vn_rewrite_uri = nil
    local uri = ngx.var.request_uri
    
    local matcher_list = config.configs['matcher']

    local re_gsub = ngx.re.gsub
    local ngx_var = ngx.var 
    local ngx_set_uri = ngx.req.set_uri
    local ngx_var_uri = ngx_var.uri
    local ngx_var_scheme = ngx_var.scheme
    local ngx_var_host = ngx_var.host

    for i, rule in ipairs( config.configs.uri_rewrite.rules ) do
        local enable = rule['enable']
        local matcher_config = matcher_list[ rule['matcher'] ] 
        if enable == true and matcher.test( matcher_config ) == true then
            replace_re = rule['replace_re']
            if replace_re ~= nil and string.len( replace_re ) >0 then
                vn_rewrite_uri = re_gsub( ngx_var_uri, replace_re, rule['to_uri'] ) 
            else
                vn_rewrite_uri = rule['to_uri']
            end

            if vn_rewrite_uri ~= ngx_var_uri then
                ngx_set_uri( vn_rewrite_uri , false )
            end
            return
        end
    end

end

return _M
