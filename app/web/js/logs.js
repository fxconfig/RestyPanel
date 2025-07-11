/**
 * logs.js - 日志分析模块
 * 处理日志文件列表、内容查看、搜索过滤和GoAccess分析功能
 */

class LogsManager {
    constructor() {
        // 日志文件列表
        this.files = Vue.ref([]);
        // 当前选中的日志文件
        this.currentFile = Vue.ref(null);
        // 日志内容
        this.content = Vue.ref([]);
        // 分页信息
        this.pagination = Vue.ref({
            current_page: 1,
            page_size: 1000,
            total_lines: 0,
            total_pages: 0
        });
        // 搜索过滤
        this.filter = Vue.ref("");
        // 加载状态
        this.isLoading = Vue.ref(false);
        // 错误信息
        this.error = Vue.ref(null);
        // 最后更新时间
        this.lastUpdateTime = Vue.ref(null);
        // GoAccess分析报告
        this.reports = Vue.ref([]);
        // 按日志文件分组的报告
        this.groupedReports = Vue.ref({});
        // 展开的报告组
        this.expandedGroups = Vue.ref({});
        // 模态框状态
        this.showReportModal = Vue.ref(false);
        // 当前报告URL
        this.currentReportUrl = Vue.ref("");
        // 快速分析成功后的临时报告链接
        this.quickReportUrl = Vue.ref(null);
        // GoAccess配置选项
        this.goaccessOptions = Vue.ref({
            log_format: "",
            date_format: "",
            time_format: ""
        });
        // 删除所有报告的确认模态框状态
        this.showDeleteAllConfirmModal = Vue.ref(false);
        
        // 绑定方法上下文
        this.init = this.init.bind(this);
        this.fetchLogFiles = this.fetchLogFiles.bind(this);
        this.fetchLogContent = this.fetchLogContent.bind(this);
        this.fetchReports = this.fetchReports.bind(this);
        this.selectFile = this.selectFile.bind(this);
        this.applyFilter = this.applyFilter.bind(this);
        this.formatReportName = this.formatReportName.bind(this);
        this.openReportModal = this.openReportModal.bind(this);
        this.closeReportModal = this.closeReportModal.bind(this);
        this.groupReportsByLogFile = this.groupReportsByLogFile.bind(this);
    }

    /**
     * 初始化日志管理器
     */
    init() {
        console.log('Initializing logs manager...');
        this.fetchLogFiles();
        this.fetchReports();
    }

    /**
     * 获取日志文件列表
     */
    async fetchLogFiles() {
        this.isLoading.value = true;
        this.error.value = null;

        try {
            const response = await api.get('/logs');
            if (response.data.success) { // Reverted to 'success' for this specific endpoint
                this.files.value = response.data.data;
                this.lastUpdateTime.value = new Date();
            } else {
                this.error.value = response.data.message || '获取日志文件失败';
            }
            
            return this.files.value;
        } catch (err) {
            this.error.value = err.message || '获取日志文件失败';
            console.error('Error fetching log files:', err);
            throw err;
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 选择日志文件并获取内容
     * @param {string} filename 文件名
     */
    async selectFile(filename) {
        this.currentFile.value = filename;
        this.pagination.value.current_page = 1;
        this.filter.value = "";
        this.quickReportUrl.value = null; // 切换文件时重置快速分析报告链接
        await this.fetchLogContent();
    }

    /**
     * 获取日志内容
     */
    async fetchLogContent() {
        if (!this.currentFile.value) return;

        this.isLoading.value = true;
        this.error.value = null;

        try {
            const params = {
                page: this.pagination.value.current_page,
                page_size: this.pagination.value.page_size,
                filter: this.filter.value
            };

            const response = await api.get(`/logs/${this.currentFile.value}`, { params });
            if (response.data.code === 200) {
                this.content.value = response.data.data.content;
                this.pagination.value = response.data.data.pagination;
                return this.content.value;
            } else {
                this.error.value = response.data.message || '获取日志内容失败';
                throw new Error(this.error.value);
            }
        } catch (err) {
            this.error.value = err.message || '获取日志内容失败';
            console.error('Error fetching log content:', err);
            throw err;
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 应用过滤器
     */
    applyFilter() {
        this.pagination.value.current_page = 1;
        return this.fetchLogContent();
    }

    /**
     * 清除过滤器
     */
    clearFilter() {
        this.filter.value = "";
        return this.applyFilter();
    }

    /**
     * 切换到指定页
     * @param {number} page 页码
     */
    goToPage(page) {
        if (page < 1 || page > this.pagination.value.total_pages) return;
        this.pagination.value.current_page = page;
        return this.fetchLogContent();
    }

    /**
     * 打开GoAccess分析模态框
     */
    openAnalyzeModal() {
        if (!this.currentFile.value) {
            showNotification('请先选择一个日志文件', 'error');
            return;
        }
        this.showReportModal.value = true;
    }

    /**
     * 关闭GoAccess分析模态框
     */
    closeAnalyzeModal() {
        this.showReportModal.value = false;
        this.currentReportUrl.value = "";
    }
    
    /**
     * 打开报告模态框
     */
    openReportModal() {
        this.showReportModal.value = true;
    }
    
    /**
     * 关闭报告模态框
     */
    closeReportModal() {
        this.showReportModal.value = false;
    }

    /**
     * 使用GoAccess进行快速分析 (一键分析)
     */
    async quickAnalyzeLog() {
        if (!this.currentFile.value) return;

        this.isLoading.value = true;
        this.error.value = null;
        this.quickReportUrl.value = null;

        try {
            // 直接调用API，不传递任何自定义选项
            const response = await api.post(`/logs/${this.currentFile.value}/analyze`, {});
            if (response.data.code === 200) {
                // 将成功生成的报告URL存储起来，用于临时"查看报告"按钮
                this.quickReportUrl.value = response.data.data.report_url;
                
                // 同时，也将其添加到历史报告列表中
                this.reports.value.unshift({
                    filename: this.currentFile.value,
                    url: response.data.data.report_url,
                    timestamp: new Date()
                });
                if (this.reports.value.length > 10) {
                    this.reports.value.pop();
                }
                
                // 重新获取报告列表以更新分组
                this.fetchReports();
                return this.quickReportUrl.value;
            } else {
                this.error.value = response.data.message || '快速分析失败';
                showNotification(this.error.value, 'error');
                throw new Error(this.error.value);
            }
        } catch (err) {
            this.error.value = err.message || '快速分析失败';
            showNotification(this.error.value, 'error');
            console.error('Error during quick analysis:', err);
            throw err;
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 使用GoAccess分析日志
     */
    async analyzeLog() {
        if (!this.currentFile.value) return;

        this.isLoading.value = true;
        this.error.value = null;

        try {
            const response = await api.post(`/logs/${this.currentFile.value}/analyze`, this.goaccessOptions.value);
            if (response.data.code === 200) {
                this.currentReportUrl.value = response.data.data.report_url;
                // 添加到报告列表
                this.reports.value.unshift({
                    filename: this.currentFile.value,
                    url: response.data.data.report_url,
                    timestamp: new Date()
                });
                // 限制报告列表大小
                if (this.reports.value.length > 10) {
                    this.reports.value.pop();
                }
                
                // 重新获取报告列表以更新分组
                this.fetchReports();
                return this.currentReportUrl.value;
            } else {
                this.error.value = response.data.message || '分析日志失败';
                throw new Error(this.error.value);
            }
        } catch (err) {
            this.error.value = err.message || '分析日志失败';
            console.error('Error analyzing log:', err);
            throw err;
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 获取所有可用的分析报告
     */
    async fetchReports() {
        this.isLoading.value = true;
        this.error.value = null;
        
        try {
            const response = await api.get('/log/reports');
            if (response.data.code === 200) {
                // Check if data is an array
                if (Array.isArray(response.data.data)) {
                    const reports = response.data.data;
                    
                    // 处理每个报告的时间戳
                    this.reports.value = reports.map(report => ({
                        ...report,
                        timestamp: new Date(report.modified * 1000)
                    }));
                    
                    // 按日志文件名分组报告
                    this.groupReportsByLogFile();
                } else {
                    // If not an array, initialize to empty array
                    this.reports.value = [];
                    this.groupedReports.value = {};
                    console.warn('Reports data is not an array:', response.data.data);
                }
                
                this.lastUpdateTime.value = new Date();
                return this.reports.value;
            } else {
                this.error.value = response.data.message || '获取报告列表失败';
                console.error('Failed to fetch reports:', response.data.message);
                // Initialize to empty array on error
                this.reports.value = [];
                this.groupedReports.value = {};
                throw new Error(this.error.value);
            }
        } catch (err) {
            this.error.value = err.message || '获取报告列表失败';
            console.error('Error fetching reports:', err);
            // Initialize to empty array on error
            this.reports.value = [];
            this.groupedReports.value = {};
            throw err;
        } finally {
            this.isLoading.value = false;
        }
    }
    
    /**
     * 格式化报告名称为更友好的显示
     * @param {string} reportName - 报告文件名
     * @returns {string} - 格式化后的名称
     */
    formatReportName(reportName) {
        if (!reportName) return 'Unknown Report';
        
        // 尝试匹配新格式: logname_report_timestamp_random.html
        const match = reportName.match(/^(.+?)_(report|realtime)_(\d+)_\d+\.html$/);
        if (match) {
            const logName = match[1];
            const type = match[2];
            const timestamp = parseInt(match[3]);
            const date = new Date(timestamp * 1000);
            
            // 格式化日期时间
            const formattedDate = date.toLocaleDateString();
            const formattedTime = date.toLocaleTimeString();
            
            return `${type === 'realtime' ? '🔄 ' : '📊 '}${logName} (${formattedDate} ${formattedTime})`;
        }
        
        // 如果不是新格式，直接返回原名称
        return reportName;
    }
    
    /**
     * 按日志文件名分组报告
     */
    groupReportsByLogFile() {
        const grouped = {};
        const newExpandedGroups = { ...this.expandedGroups.value };
        
        this.reports.value.forEach(report => {
            // Extract log filename from report name
            // Format: logname_report_timestamp_random.html or logname_realtime_timestamp_random.html
            let logFile = 'unknown.log';
            
            if (report.name) {
                // Try to extract the log name prefix from the new format
                const match = report.name.match(/^(.+?)_(report|realtime)_\d+_\d+\.html$/);
                if (match) {
                    logFile = match[1] + '.log';
                } else if (report.filename) {
                    // Fallback to the filename property if available
                    logFile = report.filename;
                }
            } else if (report.filename) {
                logFile = report.filename;
            }
            
            if (!grouped[logFile]) {
                grouped[logFile] = [];
                // 默认展开第一个分组
                if (Object.keys(grouped).length === 1) {
                    newExpandedGroups[logFile] = true;
                }
            }
            grouped[logFile].push(report);
        });
        
        this.groupedReports.value = grouped;
        this.expandedGroups.value = newExpandedGroups;
    }
    
    /**
     * 切换报告分组的展开/折叠状态
     * @param {string} logFile 日志文件名
     */
    toggleReportGroup(logFile) {
        // 创建一个新对象来更新 expandedGroups
        const newExpandedGroups = { ...this.expandedGroups.value };
        newExpandedGroups[logFile] = !newExpandedGroups[logFile];
        this.expandedGroups.value = newExpandedGroups;
    }
    
    /**
     * 删除单个报告
     * @param {string} reportName 报告文件名
     */
    deleteReport(reportName) {
        window.NotificationManager.confirm({
            title: '删除报告',
            message: `确定要删除报告<br><b>${reportName}</b>吗？<br>此操作无法撤销。`,
            confirmText: '删除',
            cancelText: '取消',
            dangerStyle: true,
            onConfirm: async () => {
                this.isLoading.value = true;
                
                try {
                    const response = await api.delete(`/log/reports/${reportName}`);
                    if (response.data.code === 200) {
                        showNotification('报告已删除', 'success');
                        this.fetchReports(); // 重新获取报告列表
                    } else {
                        showNotification(response.data.message || '删除报告失败', 'error');
                    }
                } catch (err) {
                    console.error('Error deleting report:', err);
                    showNotification(err.message || '删除报告失败', 'error');
                } finally {
                    this.isLoading.value = false;
                }
            }
        });
    }
    
    /**
     * 删除指定日志文件的所有报告
     * @param {string} logFile 日志文件名
     */
    async deleteReportsByLogFile(logFile) {
        if (!logFile || !this.groupedReports.value[logFile]) return;
        
        window.NotificationManager.confirm({
            title: `删除 ${logFile} 的报告`,
            message: `确定要删除 ${logFile} 的所有报告吗？<br>此操作无法撤销。`,
            confirmText: '删除',
            cancelText: '取消',
            dangerStyle: true,
            onConfirm: async () => {
                this.isLoading.value = true;
                
                try {
                    const reports = this.groupedReports.value[logFile];
                    let successCount = 0;
                    
                    for (const report of reports) {
                        try {
                            const response = await api.delete(`/log/reports/${report.name}`);
                            if (response.data.code === 200) {
                                successCount++;
                            }
                        } catch (err) {
                            console.error(`Error deleting report ${report.name}:`, err);
                        }
                    }
                    
                    if (successCount > 0) {
                        showNotification(`已删除 ${successCount} 个报告`, 'success');
                        this.fetchReports(); // 重新获取报告列表
                    } else {
                        showNotification('没有报告被删除', 'warning');
                    }
                } catch (err) {
                    console.error('Error in batch delete:', err);
                    showNotification('批量删除报告时出错', 'error');
                } finally {
                    this.isLoading.value = false;
                }
            }
        });
    }
    
    /**
     * 删除所有报告的确认对话框
     */
    showDeleteAllConfirmModal() {
        this.showDeleteAllConfirmModal.value = true;
    }

    /**
     * 关闭删除所有报告确认模态框
     */
    closeDeleteAllConfirmModal() {
        this.showDeleteAllConfirmModal.value = false;
    }

    /**
     * 删除所有报告
     */
    async deleteAllReports() {
        // 使用统一确认对话框
        window.NotificationManager.confirm({
            title: 'Delete All Report Files',
            message: '确定要删除所有报告吗？<br>此操作无法撤销。',
            confirmText: '删除全部',
            cancelText: '取消',
            dangerStyle: true,
            onConfirm: async () => {
                this.isLoading.value = true;
                
                try {
                    const response = await api.delete('/log/reports');
                    if (response.data.code === 200) {
                        showNotification('所有报告已删除', 'success');
                        this.reports.value = [];
                        this.groupedReports.value = {};
                    } else {
                        showNotification(response.data.message || '删除所有报告失败', 'error');
                    }
                } catch (err) {
                    console.error('Error deleting all reports:', err);
                    showNotification(err.message || '删除所有报告失败', 'error');
                } finally {
                    this.isLoading.value = false;
                }
            }
        });
    }

    /**
     * 格式化时间
     * @param {number} timestamp 时间戳
     * @returns {string} 格式化后的时间字符串
     */
    formatTime(timestamp) {
        if (!timestamp) return '';
        const date = new Date(timestamp * 1000);
        return date.toLocaleString();
    }

    /**
     * 格式化文件大小
     * @param {number} bytes 字节数
     * @returns {string} 格式化后的大小
     */
    formatSize(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    /**
     * 计算运行时间
     * @param {number} startTime 开始时间戳
     * @returns {string} 运行时间
     */
    calculateUptime(startTime) {
        if (!startTime) return '';
        const uptime = Math.floor(Date.now() / 1000) - startTime;
        const hours = Math.floor(uptime / 3600);
        const minutes = Math.floor((uptime % 3600) / 60);
        const seconds = uptime % 60;
        return `${hours}h ${minutes}m ${seconds}s`;
    }

    /**
     * 分析界面相关功能
     */

    /**
     * 打开实时分析模态框
     * @param {string} logFile 日志文件名
     */
    openRealtimeModal(logFile) {
        if (!logFile) {
            showNotification('请先选择一个日志文件', 'error');
            return;
        }
        
        // 设置当前选中的日志文件
        this.currentFile.value = logFile;
        
        // 显示加载状态
        this.isLoading.value = true;
        this.error.value = null;
        
        // 直接调用API，传递realtime参数
        api.post(`/logs/${logFile}/analyze`, {"realtime": true})
            .then(response => {
                this.isLoading.value = false;
                
                if (response.data.code === 200) {
                    // 在新标签页中打开报告
                    const reportUrl = response.data.data.report_url;
                    window.open(`${reportUrl}`, '_blank');
                    showNotification('实时分析已启动', 'success');
                    
                    // 同时，也将其添加到历史报告列表中
                    this.reports.value.unshift({
                        filename: logFile,
                        url: response.data.data.report_url,
                        timestamp: new Date()
                    });
                    if (this.reports.value.length > 10) {
                        this.reports.value.pop();
                    }
                    
                    // 重新获取报告列表以更新分组
                    this.fetchReports();
                } else {
                    this.error.value = response.data.message || '启动实时分析失败';
                    showNotification(this.error.value, 'error');
                }
            })
            .catch(err => {
                this.isLoading.value = false;
                this.error.value = err.message || '启动实时分析失败';
                showNotification(this.error.value, 'error');
            });
    }

    /**
     * 处理ESC键关闭模态框
     */
    handleEscKey() {
        if (this.showReportModal.value) {
            this.closeReportModal();
        } else if (this.showDeleteAllConfirmModal.value) {
            this.closeDeleteAllConfirmModal();
        }
    }
    
    /**
     * 关闭所有下拉菜单
     */
    closeDropdowns() {
        // 如果有任何下拉菜单，在这里实现关闭逻辑
    }
    
    /**
     * 清理资源
     */
    cleanup() {
        this.files.value = [];
        this.content.value = [];
        this.reports.value = [];
        this.groupedReports.value = {};
        this.showReportModal.value = false;
        this.showDeleteAllConfirmModal.value = false;
        this.currentFile.value = null;
        this.currentReportUrl.value = "";
        this.quickReportUrl.value = null;
    }
}

// 创建全局LogsManager类
window.LogsManager = LogsManager; 