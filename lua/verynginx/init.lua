local config = require "verynginx.config"
local keepalive = require "verynginx.keepalive"

-- 初始化keepalive检查
if config.get_config().keepalive_enable then
    local check_timer = ngx.timer.every(1, function()
        keepalive.check_all_nodes()
    end)
end 