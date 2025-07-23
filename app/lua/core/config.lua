-- -*- coding: utf-8 -*-
-- @Date    : 2016-01-02 00:51
-- @Author  : Alexa (AlexaZhou@163.com)
-- @Link    : 
-- @Disc    : 

local cjson = require "cjson"

-- 尝试引入 pretty json 输出（多行、缩进），若不可用则降级为普通 encode
-- local have_pretty, pretty = pcall(require, "resty.prettycjson")
-- if not have_pretty then
--     if ngx and ngx.log then
--         ngx.log(ngx.WARN, "resty.prettycjson not found, falling back to minified JSON output")
--     end
-- end

-- local function encode_json_pretty(tbl)
--     if have_pretty and pretty then
--         -- pretty(dt, lf, id, ac, ec) 默认使用 \n 换行, \t 缩进
--         return pretty(tbl, "\n", "    ")
--     else
--         return cjson.encode(tbl)
--     end
-- end

local _M = {}

-- 默认配置 Lua table（避免JSON解析）
local default_config = {
    
    -- API 前缀配置 (安全设置)
    base_uri = "/asd1239axasd/api",  -- 默认API前缀，建议修改为随机字符串
    dashboard_host = "",          -- 限制管理界面访问的主机名
    
    -- 请求匹配器
    matcher = {
        all_request = {},
        attack_sql_0 = {
            Args = {
                name_operator = "*",
                operator = "≈",
                value = "select.*from"
            }
        },
        attack_backup_0 = {
            URI = {
                operator = "≈",
                value = "\\.(htaccess|bash_history|ssh|sql)$"
            }
        },
        attack_scan_0 = {
            UserAgent = {
                operator = "≈",
                value = "(nmap|w3af|netsparker|nikto|fimap|wget)"
            }
        },
        attack_code_0 = {
            URI = {
                operator = "≈",
                value = "\\.(git|svn|\\.)"
            }
        },
        RestyPanel = {
            URI = {
                operator = "≈",
                value = "^/RestyPanel/"
            }
        },
        localhost = {
            IP = {
                operator = "=",
                value = "127.0.0.1"
            }
        },
        demo_RestyPanel_short_uri = {
            URI = {
                operator = "≈",
                value = "^/vn"
            }
        },
        demo_other_RestyPanel_uri = {
            URI = {
                operator = "=",
                value = "/redirect_to_RestyPanel"
            }
        }
    },
    
    -- 响应模板
    response = {
        demo_response_html = {
            content_type = "text/html",
            body = "This is a html demo response"
        },
        demo_response_json = {
            content_type = "application/json",
            body = "{\"msg\":\"soms text\",\"status\":\"success\"}"
        }
    },
    
    -- 协议锁定
    scheme_lock = {
        enable = false,
        rules = {
            {
                matcher = "RestyPanel",
                scheme = "https",
                enable = false
            }
        }
    },
    
    -- 重定向
    redirect = {
        enable = true,
        rules = {
            {
                matcher = "demo_other_RestyPanel_uri",
                to_uri = "/RestyPanel/index.html",
                enable = true
            }
        }
    },
    
    -- URI重写
    uri_rewrite = {
        enable = true,
        rules = {
            {
                matcher = "demo_RestyPanel_short_uri",
                replace_re = "^/vn/(.*)",
                to_uri = "/RestyPanel/$1",
                enable = true
            }
        }
    },
    
    -- 浏览器验证
    browser_verify = {
        enable = true,
        rules = {}
    },
    
    -- 请求过滤
    filter = {
        enable = true,
        rules = {
            {
                matcher = "localhost",
                action = "accept",
                enable = false
            },
            {
                matcher = "attack_sql_0",
                action = "block",
                code = "403",
                enable = true
            },
            {
                matcher = "attack_backup_0",
                action = "block",
                code = "403",
                enable = true
            },
            {
                matcher = "attack_scan_0",
                action = "block",
                code = "403",
                enable = true
            },
            {
                matcher = "attack_code_0",
                action = "block",
                code = "403",
                enable = true
            }
        }
    },
    
    -- 频率限制
    frequency_limit = {
        enable = true,
        rules = {}
    },
    
    -- 统计收集
    summary = {
        request_enable = true,
        with_host = false,
        group_persistent_enable = true,
        group_temporary_enable = true,
        temporary_period = 60,
        collect_rules = {}
    },
    admin = {
        enable = true,
        jwt_secret = "RestyPanel-JWT-Secret-Key-2024",  -- JWT签名密钥
        jwt_expires = 86400,  -- JWT过期时间（秒）
        users = {
            {
                user = "RestyPanel",
                password = "RestyPanel"
            }
        },
        paths = {
            logs_dir = "/var/log/nginx/",    -- 日志文件存储路径
            reports_dir = "/app/web/reports/" -- 报告文件存储路径
        }
    }
}

--  === 模块化配置管理（由原 config_manager.lua 合并） ===
local CONFIG_BASE_PATH = "/app/configs"
local MODULE_DEFAULTS = {
    admin = require("cjson").decode([[{
        "base_uri": "/asd1239axasd/api",
        "dashboard_host": "",
        "enable": true,
        "last_updated": 0,
        "paths": {
            "logs_dir": "/var/log/nginx/",
            "reports_dir": "/app/web/reports/"
        }
    }]])
}

-- 直接使用默认配置（无需JSON解析）
_M.configs = default_config

-- 缓存字典提前定义，避免初始化阶段为 nil
local _cache = {}
local _hash_cache = {}

-- 配置哈希
_M.config_hash = nil
_M.last_check_time = 0

-- 获取配置
function _M.get_configs()
    return _M.configs
end

-- 每个 request 都会更新配置（优化：减少shared memory访问频率）
function _M.update_config()
    local now = ngx.now()
    -- 每秒最多检查一次配置变化，减少shared memory访问
    if now - _M.last_check_time < 1 then
        return
    end
    _M.last_check_time = now
    
    local new_config_hash = ngx.shared.status:get('vn_config_hash')
    if new_config_hash ~= nil and new_config_hash ~= _M.config_hash then
        ngx.log(ngx.INFO, "config Hash Changed: now reload config from config.json")
        _M.load_from_file()
    end
end

-- 从文件加载配置
function _M.load_from_file()
    -- 遍历 default_config 中的一级 key（模块名）
    for module_name, module_default in pairs(default_config) do
        if type(module_default) == "table" then
            local cfg = _M.load_module_config(module_name)
            if cfg then
                -- 将模块配置覆盖到运行时 _M.configs
                _M.configs[module_name] = cfg
            end
        end
    end

    -- 记录本次加载时间作为简单哈希
    _M.config_hash = tostring(ngx.time())
    ngx.shared.status:set('vn_config_hash', _M.config_hash)
end


-- 报告当前配置
function _M.report()
    return cjson.encode(_M.configs)
end

-- touch config hash (shared)
function _M.touch_config_hash()
    local status_shm = ngx.shared.status
    if status_shm then
        status_shm:set("vn_config_hash", ngx.time())
    end
end

local function module_path(name)
    return CONFIG_BASE_PATH .. "/" .. name .. ".json"
end

local function file_exists(path)
    local f = io.open(path, "r"); if f then f:close(); return true end; return false
end

function _M.save_module_config(module_name, cfg)
    local ok, data = pcall(cjson.encode, cfg); if not ok then return false, "encode error" end
    local path = module_path(module_name)
    os.execute("mkdir -p " .. CONFIG_BASE_PATH)
    local f, err = io.open(path, "w"); if not f then return false, err end
    f:write(data); f:close()
    _cache[module_name] = cfg; _hash_cache[module_name] = ngx.md5(data)
    _M.touch_config_hash();
    return true
end

function _M.load_module_config(module_name)
    local path = module_path(module_name)
    if not file_exists(path) then
        local def = MODULE_DEFAULTS[module_name] or {}
        _M.save_module_config(module_name, def)
        return def
    end
    local f = io.open(path, "r"); if not f then return nil, "open failed" end
    local data = f:read("*a"); f:close()
    local ok, cfg = pcall(cjson.decode, data); if not ok then return nil, "decode" end
    _cache[module_name] = cfg; _hash_cache[module_name] = ngx.md5(data); return cfg
end

function _M.get_config(module_name)
    if _cache[module_name] then return _cache[module_name] end
    return _M.load_module_config(module_name)
end

function _M.set_config(module_name, cfg)
    return _M.save_module_config(module_name, cfg)
end

function _M.reload_module_config(module_name)
    _cache[module_name] = nil; _hash_cache[module_name] = nil; return _M.load_module_config(module_name)
end

function _M.get_default_config(module_name) return MODULE_DEFAULTS[module_name] end
function _M.reset_to_default(module_name) return _M.save_module_config(module_name, MODULE_DEFAULTS[module_name] or {}) end

function _M.get_all_modules_status()
    local status = {}
    for name,_ in pairs(MODULE_DEFAULTS) do
        status[name] = {file_exists=true,cached=_cache[name]~=nil,path=module_path(name),default_available=true}
    end
    return status
end



-- 移动自动加载调用至文件末尾，避免 load_module_config 为 nil
-- _M.load_from_file()

-- 确保所有函数已定义后再加载配置
_M.load_from_file()

-- 向外暴露模块表
return _M