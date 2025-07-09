-- -*- coding: utf-8 -*-
-- -- @Date    : 2015-01-27 05:56
-- -- @Author  : Alexa (AlexaZhou@163.com)
-- -- @Link    : 
-- -- @Disc    : record nginx infomation 

local json = require "cjson"

local _M = {}

local KEY_STATUS_INIT = "I_"

local KEY_START_TIME = "G_"

local KEY_TOTAL_COUNT = "F_"
local KEY_TOTAL_COUNT_SUCCESS = "H_"

local KEY_TRAFFIC_READ = "J_"
local KEY_TRAFFIC_WRITE = "K_"

local KEY_TIME_TOTAL = "L_"

function _M.init()

    local ok, err = ngx.shared.status:add( KEY_STATUS_INIT,true )
    if ok then
		ngx.shared.status:set( KEY_START_TIME, ngx.time() )
		ngx.shared.status:set( KEY_TOTAL_COUNT, 0 )
		ngx.shared.status:set( KEY_TOTAL_COUNT_SUCCESS, 0 )
		
        ngx.shared.status:set( KEY_TRAFFIC_READ, 0 )
		ngx.shared.status:set( KEY_TRAFFIC_WRITE, 0 )
		
        ngx.shared.status:set( KEY_TIME_TOTAL, 0 )
    end

end

--add global count info
function _M.log()
    ngx.shared.status:incr( KEY_TOTAL_COUNT, 1 )

    if tonumber(ngx.var.status) < 400 then
        ngx.shared.status:incr( KEY_TOTAL_COUNT_SUCCESS, 1 )
    end

    ngx.shared.status:incr( KEY_TRAFFIC_READ, ngx.var.request_length)
    ngx.shared.status:incr( KEY_TRAFFIC_WRITE, ngx.var.bytes_sent )
    ngx.shared.status:incr( KEY_TIME_TOTAL, ngx.var.request_time )

end

function _M.report()
    local report = {}
    
    -- 请求统计（确保为数字类型）
    report['request_all_count'] = ngx.shared.status:get( KEY_TOTAL_COUNT ) or 0
    report['request_success_count'] = ngx.shared.status:get( KEY_TOTAL_COUNT_SUCCESS ) or 0
    
    -- 时间相关
    report['time'] = ngx.now()
    report['boot_time'] = ngx.shared.status:get( KEY_START_TIME ) or ngx.time()
    report['response_time_total'] = ngx.shared.status:get( KEY_TIME_TOTAL ) or 0
    
    -- 连接统计（转换为数字类型）
    report['connections_active'] = tonumber(ngx.var.connections_active) or 0
    report['connections_reading'] = tonumber(ngx.var.connections_reading) or 0
    report['connections_writing'] = tonumber(ngx.var.connections_writing) or 0
    report['connections_waiting'] = tonumber(ngx.var.connections_waiting) or 0
    
    -- 流量统计（确保为数字类型）
    report['traffic_read'] = ngx.shared.status:get( KEY_TRAFFIC_READ ) or 0
    report['traffic_write'] = ngx.shared.status:get( KEY_TRAFFIC_WRITE ) or 0
    
    -- 返回Lua table，让API框架处理JSON编码
    return report
end

return _M
