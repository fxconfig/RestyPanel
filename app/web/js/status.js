// Status页面模块 - 图表管理和数据刷新

class StatusManager {
    constructor() {
        // 图表实例
        this.charts = {
            request: null,
            traffic: null,
            connection: null
        };
        
        // 时间窗口配置
        this.timeWindow = {
            maxDataPoints: 60,    // 默认60个数据点（5分钟）
            refreshInterval: 3,   // 默认3秒刷新间隔
            timeRange: 300        // 默认5分钟时间范围（秒）
        };
        
        // 历史数据存储
        this.rawData = []; // 存储原始数据点 { timestamp, data }
        
        // 当前状态数据
        this.currentData = {};
        
        // 刷新定时器
        this.refreshTimer = null;
        
        // 绑定方法
        this.fetchStatus = this.fetchStatus.bind(this);
        this.updateChartData = this.updateChartData.bind(this);
        this.initCharts = this.initCharts.bind(this);
        
        this.loadChartDataFromStorage();
    }
    
    loadChartDataFromStorage() {
        try {
            const saved = localStorage.getItem('RestyPanel_raw_data');
            if (saved) {
                const parsed = JSON.parse(saved);
                if (Array.isArray(parsed)) {
                    // 裁剪数据长度，防止 timeWindow 变更导致溢出
                    const max = this.timeWindow.maxDataPoints;
                    this.rawData = parsed.slice(-max);
                    console.log('Raw data loaded from localStorage, points:', this.rawData.length);
                }
            }
        } catch (e) {
            console.warn('Failed to load raw data from localStorage:', e);
        }
    }

    saveChartDataToStorage() {
        try {
            localStorage.setItem('RestyPanel_raw_data', JSON.stringify(this.rawData));
        } catch (e) {
            console.warn('Failed to save raw data to localStorage:', e);
        }
    }
    
    // 设置时间窗口
    setTimeWindow(timeRange) {
        // timeRange: 60(1分钟), 300(5分钟), 600(10分钟), 1800(30分钟), 3600(1小时)
        const oldMax = this.timeWindow.maxDataPoints;
        this.timeWindow.timeRange = timeRange;
        this.timeWindow.maxDataPoints = Math.ceil(timeRange / this.timeWindow.refreshInterval);
        const newMax = this.timeWindow.maxDataPoints;

        console.log('Time window updated:', {
            timeRange: timeRange + 's',
            maxDataPoints: this.timeWindow.maxDataPoints,
            refreshInterval: this.timeWindow.refreshInterval
        });

        // 裁剪历史数据
        this.rawData = this.rawData.slice(-newMax);
        this.saveChartDataToStorage();
        // 立即刷新图表
        this.updateCharts();
    }
    
    // 清空图表数据
    clearChartData() {
        this.rawData = [];
        this.initCharts();
        this.saveChartDataToStorage();
    }
    
    // 获取时间窗口选项
    getTimeWindowOptions() {
        return [
            { value: 60, label: '1分钟' },
            { value: 300, label: '5分钟' },
            { value: 600, label: '10分钟' },
            { value: 1800, label: '30分钟' },
            { value: 3600, label: '1小时' }
        ];
    }
    
    // 获取当前时间窗口信息
    getTimeWindowInfo() {
        const minutes = Math.floor(this.timeWindow.timeRange / 60);
        const seconds = this.timeWindow.timeRange % 60;
        return {
            timeRange: this.timeWindow.timeRange,
            maxDataPoints: this.timeWindow.maxDataPoints,
            refreshInterval: this.timeWindow.refreshInterval,
            displayText: seconds > 0 ? `${minutes}分${seconds}秒` : `${minutes}分钟`
        };
    }
    
    // 工具方法 - 格式化字节
    formatBytes(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }
    
    // 工具方法 - 获取当前时间字符串
    getCurrentTime() {
        return new Date().toTimeString().split(' ')[0];
    }
    
    // 处理原始数据为图表格式
    processRawDataForCharts() {
        if (this.rawData.length === 0) {
            return {
                labels: [],
                request: { all: [], success: [] },
                traffic: { read: [], write: [] },
                connection: { active: [], reading: [], writing: [] }
            };
        }
        
        const labels = [];
        const requestRates = [];
        const successRates = [];
        const readRates = [];
        const writeRates = [];
        const activeConnections = [];
        
        for (let i = 0; i < this.rawData.length; i++) {
            const point = this.rawData[i];
            labels.push(point.timestamp);
            activeConnections.push(point.data.connections_active || 0);
            
            if (i === 0) {
                // 第一个数据点，速率为0
                requestRates.push(0);
                successRates.push(0);
                readRates.push(0);
                writeRates.push(0);
            } else {
                const curr = this.rawData[i].data;
                const prev = this.rawData[i-1].data;
                const timeDiff = this.timeWindow.refreshInterval;
                
                const requestRate = Math.max(0, ((curr.request_all_count || 0) - (prev.request_all_count || 0)) / timeDiff);
                const successRate = Math.max(0, ((curr.request_success_count || 0) - (prev.request_success_count || 0)) / timeDiff);
                const readRate = Math.max(0, ((curr.traffic_read || 0) - (prev.traffic_read || 0)) / timeDiff);
                const writeRate = Math.max(0, ((curr.traffic_write || 0) - (prev.traffic_write || 0)) / timeDiff);
                
                requestRates.push(requestRate);
                successRates.push(successRate);
                readRates.push(readRate);
                writeRates.push(writeRate);
            }
        }
        
        return {
            labels,
            request: { all: requestRates, success: successRates },
            traffic: { read: readRates, write: writeRates },
            connection: { active: activeConnections }
        };
    }
    
    // 获取状态数据
    async fetchStatus() {
        try {
            const response = await ApiService.status.get();
            
            const newData = response.data;
            this.currentData = newData;
            this.updateChartData(newData);
            return newData;
        } catch (error) {
            console.error('Error fetching status:', error);
            throw error;
        }
    }
    
    // 更新图表数据
    updateChartData(data) {
        console.log('Updating chart data:', data);
        
        const currentTime = this.getCurrentTime();
        
        // 添加新数据点
        this.rawData.push({
            timestamp: currentTime,
            data: { ...data }
        });
        
        // 限制数据点数量
        if (this.rawData.length > this.timeWindow.maxDataPoints) {
            this.rawData.shift();
        }
        
        console.log('Raw data points:', this.rawData.length);
        
        // 更新图表显示
        this.updateCharts();
        this.saveChartDataToStorage();
    }
    
    // 初始化图表
    initCharts() {
        console.log('Initializing charts...');
        setTimeout(() => {
            this.destroyCharts();
            // 请求率图表
            const requestCtx = document.getElementById('requestChart');
            if (requestCtx) {
                this.charts.request = new Chart(requestCtx, {
                    type: 'line',
                    data: {
                        labels: [],
                        datasets: [
                            {
                                label: 'Total RPS',
                                data: [],
                                borderColor: '#3b82f6',
                                backgroundColor: 'rgba(59, 130, 246, 0.1)',
                                fill: true,
                                tension: 0.1,
                                pointRadius: 0,
                                pointHoverRadius: 4,
                                borderWidth: 2
                            },
                            {
                                label: 'Success RPS',
                                data: [],
                                borderColor: '#10b981',
                                backgroundColor: 'rgba(16, 185, 129, 0.1)',
                                fill: true,
                                tension: 0.1,
                                pointRadius: 0,
                                pointHoverRadius: 4,
                                borderWidth: 2
                            }
                        ]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        animation: { duration: 0 },
                        interaction: { intersect: false, mode: 'index' },
                        plugins: { legend: { display: false } },
                        scales: {
                            x: {
                                display: true,
                                grid: { color: 'rgba(0, 0, 0, 0.1)', lineWidth: 1 },
                                ticks: { font: { size: 11 }, maxTicksLimit: 10 }
                            },
                            y: {
                                beginAtZero: true,
                                grid: { color: 'rgba(0, 0, 0, 0.1)', lineWidth: 1 },
                                ticks: { font: { size: 11 } }
                            }
                        }
                    }
                });
                console.log('Request chart initialized');
            }
            
            // 网络流量图表
            const trafficCtx = document.getElementById('trafficChart');
            if (trafficCtx) {
                this.charts.traffic = new Chart(trafficCtx, {
                    type: 'line',
                    data: {
                        labels: [],
                        datasets: [
                            {
                                label: 'Read (bytes/s)',
                                data: [],
                                borderColor: '#8b5cf6',
                                backgroundColor: 'rgba(139, 92, 246, 0.1)',
                                fill: true,
                                tension: 0.1,
                                pointRadius: 0,
                                pointHoverRadius: 4,
                                borderWidth: 2
                            },
                            {
                                label: 'Write (bytes/s)',
                                data: [],
                                borderColor: '#f59e0b',
                                backgroundColor: 'rgba(245, 158, 11, 0.1)',
                                fill: true,
                                tension: 0.1,
                                pointRadius: 0,
                                pointHoverRadius: 4,
                                borderWidth: 2
                            }
                        ]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        animation: { duration: 0 },
                        interaction: { intersect: false, mode: 'index' },
                        plugins: { legend: { display: false } },
                        scales: {
                            x: {
                                display: true,
                                grid: { color: 'rgba(0, 0, 0, 0.1)', lineWidth: 1 },
                                ticks: { font: { size: 11 }, maxTicksLimit: 10 }
                            },
                            y: {
                                beginAtZero: true,
                                grid: { color: 'rgba(0, 0, 0, 0.1)', lineWidth: 1 },
                                ticks: { 
                                    font: { size: 11 },
                                    callback: function(value) {
                                        return StatusManager.prototype.formatBytes(value) + '/s';
                                    }
                                }
                            }
                        }
                    }
                });
                console.log('Traffic chart initialized');
            }
            
            // 连接数图表
            const connectionCtx = document.getElementById('connectionChart');
            if (connectionCtx) {
                this.charts.connection = new Chart(connectionCtx, {
                    type: 'line',
                    data: {
                        labels: [],
                        datasets: [
                            {
                                label: 'Active',
                                data: [],
                                borderColor: '#ef4444',
                                backgroundColor: 'rgba(239, 68, 68, 0.1)',
                                fill: true,
                                tension: 0.1,
                                pointRadius: 0,
                                pointHoverRadius: 4,
                                borderWidth: 2
                            }
                        ]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        animation: { duration: 0 },
                        interaction: { intersect: false, mode: 'index' },
                        plugins: { legend: { display: false } },
                        scales: {
                            x: {
                                display: true,
                                grid: { color: 'rgba(0, 0, 0, 0.1)', lineWidth: 1 },
                                ticks: { font: { size: 11 }, maxTicksLimit: 10 }
                            },
                            y: {
                                beginAtZero: true,
                                grid: { color: 'rgba(0, 0, 0, 0.1)', lineWidth: 1 },
                                ticks: { font: { size: 11 } }
                            }
                        }
                    }
                });
                console.log('Connection chart initialized');
            }
            
            // 断点续传：如果有历史数据，立即渲染到图表
            if (this.rawData.length > 0) {
                this.updateCharts();
            }
        }, 100);
    }
    
    // 更新图表显示
    updateCharts() {
        const chartData = this.processRawDataForCharts();
        console.log('Updating charts with processed data:', chartData);
        
        if (this.charts.request) {
            this.charts.request.data.labels = [...chartData.labels];
            this.charts.request.data.datasets[0].data = [...chartData.request.all];
            this.charts.request.data.datasets[1].data = [...chartData.request.success];
            this.charts.request.update('none');
        }
        
        if (this.charts.traffic) {
            this.charts.traffic.data.labels = [...chartData.labels];
            this.charts.traffic.data.datasets[0].data = [...chartData.traffic.read];
            this.charts.traffic.data.datasets[1].data = [...chartData.traffic.write];
            this.charts.traffic.update('none');
        }
        
        if (this.charts.connection) {
            this.charts.connection.data.labels = [...chartData.labels];
            this.charts.connection.data.datasets[0].data = [...chartData.connection.active];
            this.charts.connection.update('none');
        }
    }
    
    // 销毁图表
    destroyCharts() {
        Object.values(this.charts).forEach(chart => {
            if (chart) {
                chart.destroy();
            }
        });
        this.charts.request = null;
        this.charts.traffic = null;
        this.charts.connection = null;
        console.log('Charts destroyed');
    }
    
    // 开始自动刷新
    startAutoRefresh(interval = 3) {
        this.stopAutoRefresh(); // 先停止现有的定时器
        
        this.timeWindow.refreshInterval = interval;
        
        this.refreshTimer = setInterval(() => {
            console.log('Auto refresh triggered');
            this.fetchStatus();
        }, interval * 1000);
        
        // 立即获取一次数据
        this.fetchStatus();
        console.log('Auto refresh started with interval:', interval, 'seconds');
    }
    
    // 停止自动刷新
    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
            console.log('Auto refresh stopped');
        }
    }
    
    // 手动刷新
    async manualRefresh() {
        console.log('Manual refresh triggered');
        return await this.fetchStatus();
    }
    
    // 更新刷新间隔
    updateRefreshInterval(newInterval) {
        console.log('Refresh interval changed to:', newInterval, 'seconds');
        this.timeWindow.refreshInterval = newInterval;
        
        // 如果自动刷新正在运行，重新启动以应用新间隔
        if (this.refreshTimer) {
            this.startAutoRefresh(newInterval);
        }
    }
    
    // 清理资源
    cleanup() {
        this.stopAutoRefresh();
        this.destroyCharts();
        console.log('StatusManager cleaned up');
    }
    
    // 获取当前状态数据
    getCurrentData() {
        return this.currentData;
    }
    
    // 计算平均响应时间
    getAvgResponseTime() {
        const total = this.currentData.response_time_total || 0;
        const count = this.currentData.request_all_count || 1;
        return ((total / count) * 1000).toFixed(2);
    }
    
    // 计算系统运行时间
    getUptime() {
        if (this.currentData.boot_time) {
            const now = Math.floor(Date.now() / 1000);
            const boot = this.currentData.boot_time;
            const seconds = now - boot;
            
            const days = Math.floor(seconds / 86400);
            const hours = Math.floor((seconds % 86400) / 3600);
            const mins = Math.floor((seconds % 3600) / 60);
            
            if (days > 0) return `${days}d ${hours}h ${mins}m`;
            if (hours > 0) return `${hours}h ${mins}m`;
            return `${mins}m`;
        }
        return 'Unknown';
    }
}

// 创建全局状态管理器实例
window.StatusManager = StatusManager; 