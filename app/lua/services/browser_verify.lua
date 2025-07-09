-- -*- coding: utf-8 -*-
-- @Date    : 2015-10-25 15:56:46
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : browser verify module

local util = require "core.util"
local cjson = require "cjson"
local config = require "core.config"
local matcher = require "core.matcher"

local _M = {}

local function browser_verify_response( key )
    local status_code = config.configs.browser_verify_response_rule["status_code"]
    local response = config.configs.browser_verify_response_rule["response"]
    
    if ngx.var.arg_RestyPanel_browser_verify_tag == key then
        return
    end

    if response ~= nil then
        ngx.header.content_type = response['content_type']
        ngx.status = status_code
        ngx.say( response['body'] )
        ngx.exit( ngx.HTTP_OK )
    else
        ngx.exit( status_code )
    end
end

function _M.filter()
    if config.configs.browser_verify.enable ~= true then
        return
    end

    local ctx = ngx.ctx
    ctx.tag = "V_BROWSER_VERIFY"

    local scheme = ngx.var.scheme
    local server_name = ngx.var.server_name
    local uri = ngx.var.uri
    local request_uri = ngx.var.request_uri

    local matcher_list = config.configs['matcher']

    for i, rule in ipairs( config.configs.browser_verify.rules ) do
        local enable = rule['enable']
        local matcher_config = matcher_list[ rule['matcher'] ] 
        if enable == true and matcher.test( matcher_config ) == true then
            local key = ngx.md5( scheme .. server_name .. uri .. ngx.var.remote_addr )
            key = string.sub(key, 1, 8)
            
            browser_verify_response( key )
            
            return
        end
    end

end

return _M
