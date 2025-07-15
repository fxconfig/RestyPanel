-- logs_controller.lua
-- Controller for log analysis functionality

local logs_service = require "core.logs"
local cjson = require "cjson"
local util = require "core.util"

local _M = {}

-- Get list of available log files
function _M.get_logs()
    local logs, err = logs_service.get_log_files()
    
    if not logs then
        ngx.status = 500
        ngx.say(cjson.encode({success = false, message = "Failed to get logs: " .. (err or "unknown error")}))
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({success = true, data = logs}))
    return ngx.exit(ngx.HTTP_OK)
end

-- Get content of a specific log file with pagination and filtering
function _M.get_log_content(context)
    local filename = context.params.filename
    if not filename then
        return context.response.error("Missing filename parameter", 400)
    end
    
    -- Get query parameters for pagination and filtering
    local page = tonumber(context.query.page) or 1
    local page_size = tonumber(context.query.page_size) or 1000
    local filter = context.query.filter or ""
    
    -- Validate page size to prevent excessive resource usage
    if page_size > 5000 then
        page_size = 5000
    end
    
    local content, total_lines, err = logs_service.get_log_content(filename, page, page_size, filter)
    
    if not content then
        return context.response.error("Failed to read log: " .. (err or "unknown error"), 500)
    end
    
    return context.response.success({
        content = content,
        pagination = {
            current_page = page,
            page_size = page_size,
            total_lines = total_lines,
            total_pages = math.ceil(total_lines / page_size)
        }
    })
end

-- Analyze log file using GoAccess
function _M.analyze_log(context)
    local filename = context.params.filename
    if not filename then
        return context.response.error("Missing filename parameter", 400)
    end
    
    -- Get request body for analysis options
    local options = context.body or {}
    
    local report_path, err = logs_service.analyze_log(filename, options)
    
    if not report_path then
        return context.response.error("Failed to analyze log: " .. (err or "unknown error"), 500)
    end
    
    return context.response.success({
        report_url = report_path
    })
end

-- Get list of all available reports
function _M.get_reports(context)
    local reports, err = logs_service.get_reports()
    
    if err then
        return context.response.error("Failed to get reports: " .. err, 500)
    end
    
    if not reports then
        reports = {} -- Return empty array instead of error if no reports
    end
    
    return context.response.success(reports)
end

-- Get a specific report information
function _M.get_report(context)
    local report_name = context.params.report_name
    if not report_name then
        return context.response.error("Missing report name parameter", 400)
    end
    
    local report, err = logs_service.get_report(report_name)
    
    if not report then
        return context.response.error("Failed to get report: " .. (err or "unknown error"), 404)
    end
    
    return context.response.success(report)
end

-- Delete a specific report
function _M.delete_report(context)
    local report_name = context.params.report_name
    if not report_name then
        return context.response.error("Missing report name parameter", 400)
    end
    
    local success, err = logs_service.delete_report(report_name)
    
    if not success then
        return context.response.error("Failed to delete report: " .. (err or "unknown error"), 500)
    end
    
    return context.response.success({ deleted = true })
end

-- Delete all reports
function _M.delete_all_reports(context)
    local success, err = logs_service.delete_all_reports()
    
    if not success then
        return context.response.error("Failed to delete all reports: " .. (err or "unknown error"), 500)
    end
    
    return context.response.success({ deleted = true })
end

return _M 