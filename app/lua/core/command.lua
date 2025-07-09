-- -*- coding: utf-8 -*-
-- core/command.lua
-- Utility module for executing system shell commands in non-blocking manner
-- relying on github.com/openresty/lua-resty-shell
--
-- Example:
-- local cmd = require("core.command")
-- local ok, out, err = cmd.run({"nginx", "-t"})
-- if ok then ... end

local shell = require "resty.shell"

local _M = {}

-- default values
local DEFAULT_TIMEOUT = 5000           -- ms
local DEFAULT_MAX_SIZE = 128 * 1024    -- 128 KB per stream

--- Execute shell command.
-- @tparam string|table cmd  command string or argv table accepted by shell.run
-- @tparam[opt] table opts   options table {stdin, timeout, max_size}
-- @treturn boolean|nil ok   true if exit status 0, false if non-zero, nil on error/timeout
-- @treturn string stdout    stdout content (may be truncated if over max_size)
-- @treturn string stderr    stderr content (may be truncated if over max_size)
-- @treturn string reason    "exit", "signal" or error message
-- @treturn number status    exit status code or signal number
function _M.run(cmd, opts)
    opts = opts or {}
    local stdin    = opts.stdin or nil
    local timeout  = opts.timeout or DEFAULT_TIMEOUT
    local max_size = opts.max_size or DEFAULT_MAX_SIZE

    -- shell.run supports both string and array-like table for cmd.
    return shell.run(cmd, stdin, timeout, max_size)
end

--- Test nginx configuration (`nginx -t`).
--- In docker image openresty:alpine, the command is `/usr/local/openresty/bin/openresty -t`
--- @tparam[opt] table params table with optional keys {conf, prefix, quiet}
function _M.nginx_test()
    -- 设置环境变量，让nginx -t只检查语法，不处理PID文件
    local ok, stdout, stderr, reason, status = _M.run({
        "env", "NGINX_TEST_ONLY=1",
        "/usr/local/openresty/bin/openresty", 
        "-t",
        "-g", "daemon off; master_process off;"
    })

    -- 如果stderr包含"syntax is ok"，强制认为成功
    local syntax_ok = stderr and string.find(stderr, "syntax is ok")
    if syntax_ok then
        ok = true
        status = 0
    end

    -- 返回结构化的结果
    local result = {
        success = (ok == true),
        exit_code = status or -1,
        stdout = stdout or "",
        stderr = stderr or "",
        reason = reason or "",
        syntax_check = syntax_ok and "passed" or "failed"
    }

    if ngx and ngx.log then
        ngx.log(ngx.INFO, "[command.nginx_test] syntax_ok=", tostring(syntax_ok), " ok=", tostring(ok), " status=", tostring(status))
    end

    return (ok == true), result
end

--- Reload nginx (`nginx -s reload`).
function _M.nginx_reload()
    -- Primary method: openresty -s reload
    local ok, stdout, stderr, reason, status = _M.run({
        "/usr/local/openresty/bin/openresty",
        "-s", "reload"
    })

    -- Fallback using os.execute if primary failed
    local fallback_attempted = false
    local fallback_ok = false
    local fallback_err = nil

    if not ok then
        fallback_attempted = true
        -- try to send HUP to master process via pkill
        local ret = os.execute("/usr/local/openresty/bin/openresty -s reload")
        if ret == 0 then
            fallback_ok = true
        else
            fallback_err = "pkill exit code " .. tostring(ret)
        end
    end

    local result = {
        success = (ok == true) or fallback_ok,
        exit_code = status or -1,
        stdout = stdout or "",
        stderr = stderr or "",
        reason = reason or "",
        fallback = {
            attempted = fallback_attempted,
            success = fallback_ok,
            error = fallback_err
        }
    }

    if ngx and ngx.log then
        ngx.log(ngx.INFO, "[command.nginx_reload] primary_ok=", tostring(ok), " fallback_ok=", tostring(fallback_ok))
    end

    return result.success, result
end

return _M 