-- -*- coding: utf-8 -*-
-- @Date    : 2016-02-29 
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : some tools

local cjson = require "cjson"

local _M = {}


function _M.string_replace(s, pattern, replace, times)
    local ret = nil
    while times >= 0 do
        times =  times - 1
        local s_start,s_stop = string.find(s, pattern , 1, true ) -- 1,true means plain searches from index 1
        if s_start ~= nil and s_stop ~= nil then 
            s = string.sub( s, 1, s_start-1 ) .. replace .. string.sub( s, s_stop+1 )
        end
    end
    return s
end

function _M.existed( list, value )
    for idx,item in ipairs( list ) do
        if item == value then
            return true
        end
    end
    return false
end

function _M.ngx_ctx_dump()
    local dump_str = cjson.encode( ngx.ctx )
    ngx.var.vn_ctx_dump = dump_str
end

function _M.ngx_ctx_load()
    
    if ngx.var.vn_ctx_dump == nil then
        return
    end

    local dump_str = ngx.var.vn_ctx_dump
    if dump_str ~= '' then
        ngx.ctx = cjson.decode( dump_str ) 
    end
end

function _M.get_request_args()
    local args = ngx.req.get_uri_args()
    local post_args, err = nil,nil

    ngx.req.read_body()
    post_args, err = ngx.req.get_post_args()
    if post_args == nil then
        return args 
    end

    for k,v in pairs(post_args) do
        args[k] = v
    end

    return args
end

function _M.split(str, delimiter)
    local result = {}
    if str == nil or str == "" then
        return result
    end
    
    local pattern = string.format("([^%s]+)", delimiter)
    string.gsub(str, pattern, function(c) table.insert(result, c) end)
    
    return result
end

-- 检查目录是否存在
function _M.check_dir_exists(path)
    local shell = require "resty.shell"
    local ok, stdout, stderr, reason, status = shell.run({"test", "-d", path}, nil, 1000)
    
    if not ok or (reason == "exit" and status ~= 0) then
        return false, stderr or "Directory does not exist"
    end
    
    return true, nil
end

-- 列出目录中的文件
function _M.list_files(path)
    local shell = require "resty.shell"
    local ok, stdout, stderr, reason, status = shell.run({"ls", "-1", path}, nil, 1000)
    
    if not ok or (reason == "exit" and status ~= 0) then
        return {}, stderr or "Failed to list files"
    end
    
    local files = {}
    for file in stdout:gmatch("([^\n]+)") do
        table.insert(files, file)
    end
    
    return files
end

-- 获取文件状态信息
function _M.file_stat(path)
    local shell = require "resty.shell"
    local ok, stdout, stderr, reason, status = shell.run({"stat", "-c", "%s\\t%Y", path}, nil, 1000)
    
    if not ok or (reason == "exit" and status ~= 0) then
        return nil, stderr or "Failed to get file stats"
    end
    
    local size, mtime = stdout:match("(%d+)\\t(%d+)")
    if not size or not mtime then
        return nil, "Failed to parse file stats"
    end
    
    return {
        size = tonumber(size),
        mtime = tonumber(mtime)
    }
end

-- Shell命令转义
function _M.shell_escape(str)
    if not str then return "''" end
    return "'" .. string.gsub(str, "'", "'\\''") .. "'"
end

return _M
