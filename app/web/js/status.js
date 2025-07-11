// Status页面模块 - 图表管理和数据刷新

class StatusManager {
    constructor() {
        // 重新创建自己的statusData引用，确保它是正确的响应式对象
        this.statusData = Vue.ref({});
        this.isRefreshing = Vue.ref(false);  // 是否正在刷新
        this.autoRefresh = Vue.ref(true);    // 是否自动刷新
        this.refreshInterval = Vue.ref(3);  // 刷新间隔(秒)
        this.timeWindow = Vue.ref(300);     // 时间窗口(秒)

        // 图表实例
        this.charts = {
            request: null,
            traffic: null,
            connection: null
        };

        // 历史数据存储
        this.rawData = []; // 存储原始数据点 { timestamp, data }

        // 刷新定时器
        this.refreshTimer = null;

        // 绑定方法
        this.fetchStatus = this.fetchStatus.bind(this);
        this.updateChartData = this.updateChartData.bind(this);
        this.initCharts = this.initCharts.bind(this);
    }

    // 初始化状态页面
    initStatusPage() {
        console.log('Initializing status page...');
    //console.log('statusData已设置:', this.statusData);

    // 加载历史数据
        this.loadChartDataFromStorage();

        // 初始化图表
        this.initCharts();

        // 如果开启自动刷新，启动刷新
        if (this.autoRefresh && this.autoRefresh.value && this.refreshInterval) {
            this.startAutoRefresh(parseInt(this.refreshInterval.value));
        }

        // 第一次加载数据
        this.fetchStatus();
        console.log('First data fetch initiated');
    }

    // 切换自动刷新状态
    toggleAutoRefresh() {
        if (this.autoRefresh && this.refreshInterval) {
            if (this.autoRefresh.value) {
                this.startAutoRefresh(parseInt(this.refreshInterval.value));
            } else {
                this.stopAutoRefresh();
            }
        }
    }

    // 从本地存储加载数据
    loadChartDataFromStorage() {
        try {
            const saved = localStorage.getItem('RestyPanel_raw_data');
            if (saved) {
                const parsed = JSON.parse(saved);
                if (Array.isArray(parsed)) {
                    // 裁剪数据长度，防止 timeWindow 变更导致溢出
                    const maxPoints = this.timeWindow ?
                        Math.ceil(this.timeWindow.value / (this.refreshInterval?.value || 3)) : 60;
                    this.rawData = parsed.slice(-maxPoints);
                    console.log('Raw data loaded from localStorage, points:', this.rawData.length);
                }
            }
        } catch (e) {
            console.warn('Failed to load raw data from localStorage:', e);
        }
    }

    // 保存数据到本地存储
    saveChartDataToStorage() {
        try {
            localStorage.setItem('RestyPanel_raw_data', JSON.stringify(this.rawData));
        } catch (e) {
            console.warn('Failed to save raw data to localStorage:', e);
        }
    }

    // 设置时间窗口
    setTimeWindow() {
        if (!this.timeWindow || !this.refreshInterval) return;

        const timeRange = this.timeWindow.value;
        const maxPoints = Math.ceil(timeRange / this.refreshInterval.value);

        console.log('Time window updated:', {
            timeRange: timeRange + 's',
            maxDataPoints: maxPoints,
            refreshInterval: this.refreshInterval.value
        });

        // 裁剪历史数据
        if (this.rawData.length > 0) {
            this.rawData = this.rawData.slice(-maxPoints);
            this.saveChartDataToStorage();
            // 立即刷新图表
            this.updateCharts();
        }
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
                const prev = this.rawData[i - 1].data;
                const timeDiff = this.refreshInterval?.value || 3; // Use optional chaining

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
        this.isRefreshing.value = true;

        try {
            // 获取API响应
            const response = await ApiService.status.get();
            
            // 详细记录API返回的内容
            // console.log('API完整响应:', response);

            // 根据控制台输出，正确的API格式是: 
            // response = { message: "Success", data: {...实际数据...}, code: 200 }
            // 我们需要直接提取 response.data (不是response.data.data)

            if (response && response.data) {
                // 直接使用 response.data 作为我们的数据
                const statusData = response.data;
                // console.log('提取的状态数据:', statusData);

                // 直接替换状态数据，不使用Object.assign
                this.statusData.value = statusData;
                // console.log('状态数据已更新:', this.statusData.value);

                // 更新图表数据
                this.updateChartData(statusData);
                return statusData;
            } else {
                console.error('API响应缺少data字段:', response);
                return {};
            }
        } catch (error) {
            console.error('Error fetching status:', error);
            throw error;
        } finally {
            if (this.isRefreshing) {
                this.isRefreshing.value = false;
            }
        }
    }

    // 更新图表数据
    updateChartData(data) {
        const currentTime = this.getCurrentTime();

        // 添加新数据点
        this.rawData.push({
            timestamp: currentTime,
            data: { ...data }
        });

        // 限制数据点数量
        if (this.rawData.length > this.timeWindow?.value) { // Use optional chaining
            this.rawData.shift();
        }

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
                                    callback: (value) => this.formatBytes(value) + '/s'
                                }
                            }
                        }
                    }
                });
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

        this.refreshTimer = setInterval(() => {
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
            console.log('API status Auto refresh stopped');
        }
    }

    // 手动刷新
    async manualRefresh() {
        return await this.fetchStatus();
    }

    // 更新刷新间隔
    updateRefreshInterval() {

        const newInterval = parseInt(this.refreshInterval.value);
        console.log('Refresh interval changed to:', newInterval, 'seconds');

        // 如果自动刷新正在运行，重新启动以应用新间隔
        if (this.refreshTimer) {
            this.startAutoRefresh(newInterval);
        }
    }

    // 清理资源
    cleanup() {
        this.stopAutoRefresh();
        this.destroyCharts();
        this.statusData = null;
        this.isRefreshing = null;
        this.autoRefresh = null;
        this.refreshInterval = null;
        this.timeWindow = null;
        console.log('StatusManager cleaned up');
    }


    // 获取当前时间字符串
    getCurrentTime = () => {
        return new Date().toTimeString().split(' ')[0];
    }
    
    formatBytes = (bytes) => {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

}

// 创建全局状态管理器类
//window.StatusManager = StatusManager; 