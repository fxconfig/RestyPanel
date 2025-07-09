-- -*- coding: utf-8 -*-
-- @Date    : 2024-01-01
-- @Author  : RestyPanel Team
-- @Disc    : 配置管理辅助工具

local config = require "core.config"

local _M = {}

-- 通用的配置保存函数，供控制器使用
function _M.save_config(module_name)
    local module_config = config.get_config(module_name)
    local success, err = config.save_module_config(module_name, module_config)
    
    if not success then
        ngx.log(ngx.ERR, "Failed to save " .. module_name .. " config: " .. (err or "unknown error"))
        return false, err
    end
    
    -- 通知其他 worker
    config.touch_config_hash()
    
    return true, nil
end

-- 获取模块配置的快捷方式
function _M.get_config(module_name)
    return config.get_config(module_name)
end

-- 更新模块配置的快捷方式
function _M.update_config(module_name, cfg)
    local success, err = config.set_config(module_name, cfg)
    
    if not success then
        ngx.log(ngx.ERR, "Failed to update " .. module_name .. " config: " .. (err or "unknown error"))
        return false, err
    end
    
    -- 通知其他 worker
    config.touch_config_hash()
    
    return true, nil
end

-- 为控制器提供统一的配置操作接口
function _M.create_config_interface(module_name)
    return {
        get = function()
            return config.get_config(module_name)
        end,
        
        set = function(data)
            return config.set_config(module_name, data)
        end,
        
        save = function()
            return _M.save_config(module_name)
        end,
        
        reload = function()
            return config.reload_module_config(module_name)
        end,
        
        reset = function()
            return config.reset_to_default(module_name)
        end,
        
        backup = function()
            return false, "backup_not_impl"
        end,
        
        get_default = function()
            return config.get_default_config(module_name)
        end
    }
end


return _M 