-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team  
-- @Disc    : 高效匹配器模块 - 直接使用ngx变量，无兼容性开销

local _M = {}
local matcher_funcs = {}

-- Helper function to check if a value is a table of conditions
local function is_condition_table(value)
    return type(value) == 'table' and (value['operator'] or value['name'] or value['conditions'])
end

-- Helper function to check if a value is a logical operator
local function is_logical_operator(value)
    return type(value) == 'string' and (value == 'AND' or value == 'OR')
end

-- ============= 主要匹配函数 =============

function _M.check_if_hit( matcher )
    if matcher == nil then
        return false
    end

    -- Check if matcher has logical operator
    local logical_op = matcher['logical_operator'] or 'AND'
    if logical_op ~= 'AND' and logical_op ~= 'OR' then
        logical_op = 'AND' -- default to AND
    end

    local results = {}
    local has_conditions = false

    for name, v in pairs( matcher ) do
        -- Skip logical operator field
        if name ~= 'logical_operator' then
            if matcher_funcs[name] ~= nil then
                has_conditions = true
                local result = matcher_funcs[name]( v )
                table.insert(results, result)
            end
        end
    end

    if not has_conditions then
        return false
    end

    -- Apply logical operator
    if logical_op == 'AND' then
        for _, result in ipairs(results) do
            if result ~= true then
                return false
            end
        end
        return true
    elseif logical_op == 'OR' then
        for _, result in ipairs(results) do
            if result == true then
                return true
            end
        end
        return false
    end

    return false
end

-- ============= 简化的API =============

-- 简化的测试方法 - 直接使用当前请求
function _M.test(matcher_config)
    if not matcher_config or type(matcher_config) ~= "table" then
        return false
    end
    
    -- 如果matcher为空，匹配所有请求
    if next(matcher_config) == nil then
        return true
    end
    
    return _M.check_if_hit(matcher_config)
end

-- ============= 基础测试函数 =============

--test_var is a basic test method, used by other test method
function _M.test_var( match_operator, match_value, target_var )
    local str_target = tostring(target_var or "")
    local str_match = tostring(match_value or "")

    if match_operator == "=" then
        return str_target == str_match
    elseif match_operator == "==" then
        return target_var == match_value
    elseif match_operator == "*" then
        return true
    elseif match_operator == "#" then
        if type(match_value) == 'table' then
            for k, v in pairs(match_value) do
                if string.lower(tostring(v)) == string.lower(str_target) then
                    return true
                end
            end
        end
        return false
    elseif match_operator == "!=" then
        return str_target ~= str_match
    elseif match_operator == '≈' or match_operator == "~" then
        if type(target_var) == 'string' then
            return ngx.re.find( target_var, match_value, 'isjo' ) ~= nil
        end
        return false
    elseif match_operator == '!≈' or match_operator == "!~" then
        if type(target_var) ~= 'string' then
            return true
        end
        return ngx.re.find( target_var, match_value, 'isjo' ) == nil
    elseif match_operator == 'Exist' then
        return target_var ~= nil
    elseif match_operator == '!Exist' then
        return target_var == nil
    elseif match_operator == '!' then
        return target_var == nil or str_target == ""
    elseif match_operator == ">" then
        local num_target = tonumber(str_target)
        local num_match = tonumber(str_match)
        if num_target and num_match then
            return num_target > num_match
        end
        return str_target > str_match
    elseif match_operator == "<" then
        local num_target = tonumber(str_target)
        local num_match = tonumber(str_match)
        if num_target and num_match then
            return num_target < num_match
        end
        return str_target < str_match
    elseif match_operator == ">=" then
        local num_target = tonumber(str_target)
        local num_match = tonumber(str_match)
        if num_target and num_match then
            return num_target >= num_match
        end
        return str_target >= str_match
    elseif match_operator == "<=" then
        local num_target = tonumber(str_target)
        local num_match = tonumber(str_match)
        if num_target and num_match then
            return num_target <= num_match
        end
        return str_target <= str_match
    elseif match_operator == "in" then
        return string.find(str_target, str_match, 1, true) ~= nil
    elseif match_operator == "!in" then
        return string.find(str_target, str_match, 1, true) == nil
    end

    return false
end

--test a group of var in table with a condition
function _M.test_many_var( var_table, condition )
    if not var_table or type(var_table) ~= "table" then
        return false
    end

    local name_operator = condition['name_operator'] or "="
    local name_value = condition['name'] or condition['name_value']
    local operator = condition['operator'] or condition['value_operator']
    local value = condition['value']

    -- Insert !Exist Check here as it is only applied to operator
    if operator == '!Exist' then
        for k, v in pairs(var_table) do
            if _M.test_var( name_operator, name_value, k ) == true then
                return false
            end
        end
        return true
    else
        -- Normal process
        for k, v in pairs(var_table) do
            if _M.test_var( name_operator, name_value, k ) == true then
                -- 处理数组类型的值
                if type(v) == "table" then
                    for _, array_value in ipairs(v) do
                        if _M.test_var( operator, value, array_value ) == true then
                            return true
                        end
                    end
                else
                    if _M.test_var( operator, value, v ) == true then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- ============= 字段测试函数 =============

function _M.test_uri( condition )
    local uri = ngx.var.uri;
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_var( cond['operator'], cond['value'], uri ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_var( cond['operator'], cond['value'], uri ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_var( condition['operator'], condition['value'], uri )
end

function _M.test_ip( condition )
    local ipv4 = ngx.req.get_headers()["X-Real-IP"]
    if ipv4 == nil then
        ipv4 = ngx.req.get_headers()["X-Forwarded-For"]
    end
    if ipv4 == nil then
        ipv4 = ngx.var.remote_addr
    end
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_var( cond['operator'], cond['value'], ipv4 ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_var( cond['operator'], cond['value'], ipv4 ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_var( condition['operator'], condition['value'], ipv4 )
end

function _M.test_uid( condition )
    -- 尝试从JWT获取用户ID，如果失败则返回nil
    local uid = nil
    local success, comm = pcall(require, "resty.panel.lib.comm")
    if success and comm and comm.get_user_id_from_jwt then
        uid = comm.get_user_id_from_jwt()
    end
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_var( cond['operator'], cond['value'], uid ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_var( cond['operator'], cond['value'], uid ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_var( condition['operator'], condition['value'], uid )
end

function _M.test_ua( condition )
    local http_user_agent = ngx.var.http_user_agent;
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_var( cond['operator'], cond['value'], http_user_agent ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_var( cond['operator'], cond['value'], http_user_agent ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_var( condition['operator'], condition['value'], http_user_agent )
end

function _M.test_referer( condition )
    local http_referer = ngx.var.http_referer;
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_var( cond['operator'], cond['value'], http_referer ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_var( cond['operator'], cond['value'], http_referer ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_var( condition['operator'], condition['value'], http_referer )
end

function _M.test_method( condition )
    local method_name = ngx.req.get_method()
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_var( cond['operator'], cond['value'], method_name ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_var( cond['operator'], cond['value'], method_name ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_var( condition['operator'], condition['value'], method_name )
end

function _M.test_args( condition )
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_single_arg_condition(cond) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_single_arg_condition(cond) then
                    return true
                end
            end
            return false
        end
    end
    
    -- 处理传统的参数测试方式
    if condition.name_operator or condition.name_value or condition.name then
        return _M.test_single_arg_condition(condition)
    end
    
    -- 检查 URI 参数
    local uri_args = ngx.req.get_uri_args()
    if _M.test_many_var(uri_args, condition) then
        return true
    end
    
    -- 检查 POST 参数
    ngx.req.read_body()
    if ngx.req.get_body_file() == nil then
        local body_args, err = ngx.req.get_post_args()
        if body_args then
            return _M.test_many_var(body_args, condition)
        end
    end
    
    return false
end

-- Helper function to test a single arg condition
function _M.test_single_arg_condition( condition )
    local name_operator = condition['name_operator']  or '≈'
    local name_value = condition['name']
    local operator = condition['operator'] or condition['value_operator']
    local value = condition['value']

    --handle args behind uri
    for k,v in pairs( ngx.req.get_uri_args()) do
        if _M.test_var( name_operator, name_value, k ) == true then
            if type(v) == "table" then
                for arg_idx,arg_value in ipairs(v) do
                    if _M.test_var( operator, value, arg_value ) == true then
                        return true
                    end
                end
            else
                if _M.test_var( operator, value, v ) == true then
                    return true
                end
            end
        end
    end

    return false
end

function _M.test_body( condition )
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_single_body_condition(cond) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_single_body_condition(cond) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_single_body_condition(condition)
end

-- Helper function to test a single body condition
function _M.test_single_body_condition( condition )
    local name_operator = condition['name_operator'] or '≈'
    local name_value = condition['name']
    local operator = condition['operator'] or condition['value_operator']
    local value = condition['value']

    -- 安全读取请求体
    ngx.req.read_body()
    
    -- 检查是否缓存到临时文件
    if ngx.req.get_body_file() ~= nil then
        return false
    end

    -- 尝试获取解析后的请求体参数
    local body_args, err = ngx.req.get_post_args()
    if not body_args then
        return false
    end

    -- 检查解析后的参数
    for k, v in pairs(body_args) do
        if _M.test_var(name_operator, name_value, k) == true then
            if type(v) == "table" then
                for arg_idx, arg_value in ipairs(v) do
                    if _M.test_var(operator, value, arg_value) == true then
                        return true
                    end
                end
            else
                if _M.test_var(operator, value, v) == true then
                    return true
                end
            end
        end
    end

    return false
end

function _M.test_host( condition )
    local hostname = ngx.var.host
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_var( cond['operator'], cond['value'], hostname ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_var( cond['operator'], cond['value'], hostname ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_var( condition['operator'], condition['value'], hostname )
end

function _M.test_header( condition )
    local header_table = ngx.req.get_headers()
    
    -- Check if condition is a table of multiple conditions
    if type(condition) == 'table' and condition['conditions'] then
        local logical_op = condition['logical_operator'] or 'AND'
        local conditions = condition['conditions']
        
        if logical_op == 'AND' then
            for _, cond in ipairs(conditions) do
                if not _M.test_many_var( header_table, cond ) then
                    return false
                end
            end
            return true
        elseif logical_op == 'OR' then
            for _, cond in ipairs(conditions) do
                if _M.test_many_var( header_table, cond ) then
                    return true
                end
            end
            return false
        end
    end
    
    -- Single condition (backward compatibility)
    return _M.test_many_var( header_table, condition )
end

-- ============= 函数映射 =============

matcher_funcs["URI"] = _M.test_uri
matcher_funcs["IP"] = _M.test_ip
matcher_funcs["UserAgent"] = _M.test_ua
matcher_funcs["Method"] = _M.test_method
matcher_funcs["Args"] = _M.test_args
matcher_funcs["Body"] = _M.test_body
matcher_funcs["Referer"] = _M.test_referer
matcher_funcs["Host"] = _M.test_host
matcher_funcs["Header"] = _M.test_header
matcher_funcs["UID"] = _M.test_uid

return _M 