local summary = require "services.summary"
local filter  = require "services.filter"
local browser_verify  = require "services.browser_verify"
local frequency_limit = require "services.frequency_limit"

-- 如果设置了api_mode标志，说明请求已被API location处理，直接返回
if ngx.var.vn_exec_flag and ngx.var.vn_exec_flag== 'api_mode' then
    return
end

-- 如果设置了其他执行标志，也直接返回
if ngx.var.vn_exec_flag and ngx.var.vn_exec_flag ~= '' then
    return
end

-- 执行常规的访问控制和安全检查（仅对非API请求）
summary.pre_run_matcher()

filter.filter()
browser_verify.filter()
frequency_limit.filter()

-- 注意：API请求现在由nginx location直接处理，不再经过此文件
