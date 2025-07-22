// Upstreams页面模块 - 后端服务器管理

class UpstreamsManager {
    constructor() {
        // 基础数据
        const savedData = localStorage.getItem('RestyPanel_upstreamsData');
        this.data = Vue.ref(savedData ? JSON.parse(savedData) : []);
        this.isLoading = Vue.ref(false);
        this.lastUpdateTime = Vue.ref(null);

        // 刷新相关
        this.statusRefreshTimer = Vue.ref(null);
        this.autoRefresh = Vue.ref(true);
        this.refreshInterval = Vue.ref(3);
        
        // 编辑模态框相关
        this.showEditModal = Vue.ref(false);
        this.editingUpstream = Vue.ref(null);
        this.editingConfigText = Vue.ref('');
        this.editError = Vue.ref('');
        this.isSaving = Vue.ref(false);

        // 展示 upstream.conf 相关
        this.showConfModal = Vue.ref(false);
        this.upstreamConfContent = Vue.ref('');
        this.confError = Vue.ref('');
        this.confViewerInstance = null;

        // 健康检查模态框相关
        this.showHealthCheckerModal = Vue.ref(false);
        this.healthCheckerForm = Vue.reactive({
            type: 'http',
            http_req: 'GET /status HTTP/1.0\r\nHost: foo.com\r\n\r\n',
            port: '',
            interval: 6000,
            timeout: 3000,
            fall: 1,
            rise: 1,
            valid_statuses: '200,302',
            concurrency: 10,
            ssl_verify: false,
            host: ''
        });
        this.healthCheckerError = Vue.ref('');
        this.currentEditingUpstream = null;

        // Dropdown and Add Server Modal
        this.activeDropdown = Vue.ref(null);
        this.showAddServerModal = Vue.ref(false);
        this.currentUpstreamForAddServer = Vue.ref(null);
        this.addServerForm = Vue.ref({ address: '', weight: 1 });
        this.addServerError = Vue.ref('');

        // Delete Server confirmation modal
        this.showDeleteServerModal = Vue.ref(false);

        // 绑定方法上下文
        this.parseUpstreamStatus = this.parseUpstreamStatus.bind(this);
        this.updateUpstreamStatus = this.updateUpstreamStatus.bind(this);
    }

    // 初始化
    init() {
        console.log('Initializing upstreams manager...');
        // 加载upstream数据
        this.fetchUpstreams().then(() => {
            // 加载完成后更新状态
            this.updateUpstreamStatus();

            // 如果开启了自动刷新，启动定时刷新
            if (this.autoRefresh.value) {
                this.startStatusRefresh();
            }
        });
    }
    
    // 解析 /upstream/status 文本
    parseUpstreamStatus(text) {
        const statusMap = {};
        const noCheckersMap = {};
        let current = null;
        let isPrimary = false;
        let isBackup = false;
        
        text.split(/\r?\n/).forEach(line => {
            const trimmed = line.trim();
            // 匹配 Upstream 行
            const upMatch = trimmed.match(/^Upstream\s+([^\s]+)(.*)$/i);
            if (upMatch) {
                current = upMatch[1];
                statusMap[current] = {};
                // 检查是否包含 "NO checkers"
                noCheckersMap[current] = upMatch[2].includes('NO checkers');
                isPrimary = false;
                isBackup = false;
                return;
            }
            
            if (!current) return;
            
            // 检查是否是Primary Peers或Backup Peers段落
            if (trimmed === 'Primary Peers') {
                isPrimary = true;
                isBackup = false;
                return;
            } else if (trimmed === 'Backup Peers') {
                isPrimary = false;
                isBackup = true;
                return;
            }
            
            // 匹配服务器地址和状态 - 更精确的匹配
            if (isPrimary || isBackup) {
                const peerMatch = trimmed.match(/^(\d+\.\d+\.\d+\.\d+:\d+)\s+(\w+)/);
                if (peerMatch) {
                    // 添加到状态映射，设置服务器类型
                    const address = peerMatch[1];
                    const status = peerMatch[2];
                    statusMap[current][address] = status;
                }
            }
        });
        
        return { statusMap, noCheckersMap };
    }
    
    // 获取 upstream 列表（只保存原始配置数据）
    async fetchUpstreams() {
        try {
            this.isLoading.value = true;
            const listResp = await ApiService.upstreams.list();

            const upstreams = listResp.data.map(u => {
                // 保存原始配置数据
                const rawConfig = { ...u };
                
                // 前端显示用的服务器列表（不修改原始数据）
                const displayServers = this.parseServersFromConfig(u.servers || []);

                return {
                    // 原始配置数据（不修改）
                    rawConfig: rawConfig,

                    // 前端显示数据
                    name: u.name,
                    servers: displayServers,
                    enable: u.enable !== false, // 从原始数据获取
                    hasCheckers: true, // 前端状态
                    isToggling: false // 前端状态
                };
            });

            // 按照名称字母顺序排序
            upstreams.sort((a, b) => a.name.localeCompare(b.name));

            this.data.value = upstreams;
            this.saveDataToStorage();

            return upstreams;
        } catch (err) {
            console.error('Error fetching upstreams:', err);
            throw err;
        } finally {
            this.isLoading.value = false;
        }
    }

    // 解析服务器配置
    parseServersFromConfig(servers) {
        return (servers || []).map(s => {
            let address = '';
            let weight;
            let enable = true; // 默认启用

            if (typeof s === 'string') {
                address = s;
            } else {
                if (s.server) address = s.server;
                else if (s.host) address = s.port ? `${s.host}:${s.port}` : s.host;
                else if (s.address) address = s.address;
                weight = s.weight;
                enable = s.enable !== false; // 明确检查 enable 字段，默认为 true
            }

            return {
                address,
                weight,
                status: 'UNKNOWN', // 前端状态
                enable, // 从原始数据获取
                isToggling: false // 前端状态
            };
        });
    }

    // 保存数据到本地存储
    saveDataToStorage() {
        localStorage.setItem('RestyPanel_upstreamsData', JSON.stringify(this.data.value));
    }
    
    // 手动刷新
    refreshUpstreams() {
        return this.fetchUpstreams().then(() => this.updateUpstreamStatus());
    }
    
    // 更新upstream状态（根据upstream/status接口）
    async updateUpstreamStatus() {
        try {
            const statusResp = await ApiService.upstreams.status();
            
            const statusText = statusResp.data.status_page;
            const { statusMap, noCheckersMap } = this.parseUpstreamStatus(statusText);
            
            // 更新前端显示状态
            this.data.value.forEach(upstream => {
                // 更新upstream的checker状态（前端状态）
                upstream.hasCheckers = !noCheckersMap[upstream.name];
                
                // 查找状态中存在但配置中不存在的服务器
                if (statusMap[upstream.name] && !noCheckersMap[upstream.name]) {
                    this.updateDynamicServers(upstream, statusMap);
                }

                // 更新每个server的状态（前端状态）
                upstream.servers.forEach(server => {
                    if (noCheckersMap[upstream.name]) {
                        server.status = 'UNKNOWN';
                    } else {
                        server.status = statusMap[upstream.name]?.[server.address] || 'UNKNOWN';
                    }
                });
            });

            // 记录最后更新时间并添加心跳动画
            this.lastUpdateTime.value = new Date();

            // 为最后更新时间添加心跳动画效果
            Vue.nextTick(() => {
                const lastUpdateTimeElement = document.querySelector('.action-bar .last-update-time');
                if (lastUpdateTimeElement) {
                    // 添加心跳类
                    lastUpdateTimeElement.classList.add('heartbeat');

                    // 动画结束后移除类
                    setTimeout(() => {
                        lastUpdateTimeElement.classList.remove('heartbeat');
                    }, 1500); // 与动画时长相匹配
                }
            });

            return this.data.value;
        } catch (err) {
            console.error('Error updating upstream status:', err);
            throw err;
        }
    }

    // 更新动态服务器
    updateDynamicServers(upstream, statusMap) {
        const configuredAddresses = upstream.servers.filter(s => !s.isDynamic).map(s => s.address);
        const statusAddresses = Object.keys(statusMap[upstream.name]);

        // 找出状态中有但配置中没有的服务器地址
        const dynamicServers = statusAddresses.filter(addr => !configuredAddresses.includes(addr));

        // 先移除已不存在于状态中的动态服务器
        const currentDynamicServers = upstream.servers.filter(s => s.isDynamic);
        const toRemove = [];

        currentDynamicServers.forEach(server => {
            if (!statusAddresses.includes(server.address)) {
                toRemove.push(server.address);
            }
        });

        // 移除不再出现在状态中的动态服务器
        if (toRemove.length > 0) {
            upstream.servers = upstream.servers.filter(s => !s.isDynamic || !toRemove.includes(s.address));
        }

        // 添加新的动态服务器
        const existingDynamicAddresses = upstream.servers.filter(s => s.isDynamic).map(s => s.address);

        dynamicServers.forEach(address => {
            // 只添加尚未存在的动态服务器
            if (!existingDynamicAddresses.includes(address)) {
                upstream.servers.push({
                    address,
                    isDynamic: true, // 标记为动态/不可编辑
                    status: statusMap[upstream.name][address],
                    enable: true,
                    isToggling: false
                });
            }
        });
    }

    // 自动刷新相关方法
    
    // 停止定时刷新
    stopStatusRefresh() {
        if (this.statusRefreshTimer.value) {
            clearInterval(this.statusRefreshTimer.value);
            this.statusRefreshTimer.value = null;
            console.log('Upstream status Auto refresh stopped');
        }
    }
    
    // 切换自动刷新
    toggleAutoRefresh() {
        if (this.autoRefresh.value) {
            this.startStatusRefresh();
        } else {
            this.stopStatusRefresh();
        }
    }
    
    // 更新刷新间隔
    updateRefreshInterval() {
        // 如果正在自动刷新，立即重启定时器以应用新间隔
        if (this.autoRefresh.value) {
            this.startStatusRefresh();
        }
    }
    
    // 定时刷新 upstream status
    startStatusRefresh() {
        this.stopStatusRefresh();

        this.statusRefreshTimer.value = setInterval(() => {
            this.updateUpstreamStatus();
        }, this.refreshInterval.value * 1000); // 使用设置的间隔
    }
    
    // 切换 upstream 启用状态（只修改enable字段）
    async toggleUpstream(upstreamName, enabled) {
        const upstream = this.data.value.find(u => u.name === upstreamName);
        if (!upstream) return;

        try {
        // 设置loading状态
            upstream.isToggling = true;
            
            // 修改配置
            upstream.rawConfig.enable = enabled;
            
            // 调用API更新upstream
            const resp = await ApiService.upstreams.update(upstreamName, upstream.rawConfig);
            
            // 使用返回的数据更新界面
            const returnedConfig = resp.data;

            // 更新配置和UI
            this.updateUpstreamFromConfig(upstream, returnedConfig);
            
            // 重新拉取状态
            await this.updateUpstreamStatus();
            
            // 显示成功通知
            if (window.showNotification) {
                const actualEnabled = returnedConfig.enable !== false;
                window.showNotification('success', `Upstream "${upstreamName}" ${actualEnabled ? 'enabled' : 'disabled'} successfully`);
            }
        } catch (err) {
            console.error('Error toggling upstream:', err);
            // 显示错误通知
            if (window.showNotification) {
                window.showNotification('error', err?.message || 'Failed to update upstream');
            }
        } finally {
            // 清除loading状态
            upstream.isToggling = false;
        }
    }
    
    // 切换 server 启用状态（只修改对应server的enable字段）
    async toggleServer(upstreamName, serverAddress, enabled) {
        // 找到对应的upstream和server
        const upstream = this.data.value.find(u => u.name === upstreamName);
        if (!upstream) return;

        const server = upstream.servers.find(s => s.address === serverAddress);
        if (!server) return;

        try {
            server.isToggling = true;
            
            // 修改原始配置中的服务器enable状态
            this.updateServerInRawConfig(upstream, serverAddress, enabled);
            
            // 调用API更新upstream
            const resp = await ApiService.upstreams.update(upstreamName, upstream.rawConfig);
            if (!resp || resp.code !== 200) {
                // 显示错误通知
                if (window.showNotification) {
                    window.showNotification('error', resp?.message || 'Failed to update server');
                }
                return;
            }
            
            // 更新配置和UI
            this.updateUpstreamFromConfig(upstream, resp.data);
            
            // 重新拉取状态
            await this.updateUpstreamStatus();
            
            // 显示成功通知
            if (window.showNotification) {
                window.showNotification('success', `Server "${serverAddress}" ${enabled ? 'enabled' : 'disabled'} successfully`);
            }
        } catch (err) {
            console.error('Error toggling server:', err);
            // 显示错误通知
            if (window.showNotification) {
                window.showNotification('error', err?.message || 'Failed to update server');
            }
        } finally {
            // 清除loading状态
            const server = upstream.servers.find(s => s.address === serverAddress);
            if (server) {
                server.isToggling = false;
            }
        }
    }
    
    // 更新原始配置中的服务器enable状态
    updateServerInRawConfig(upstream, serverAddress, enabled) {
        if (!upstream.rawConfig.servers) return;

        for (let i = 0; i < upstream.rawConfig.servers.length; i++) {
            const s = upstream.rawConfig.servers[i];
            let isTargetServer = false;
            
            if (typeof s === 'string' && s === serverAddress) {
                isTargetServer = true;
            } else if (s.server && s.server === serverAddress) {
                isTargetServer = true;
            } else if (s.host && s.port && `${s.host}:${s.port}` === serverAddress) {
                isTargetServer = true;
            } else if (s.host && !s.port && s.host === serverAddress) {
                isTargetServer = true;
            } else if (s.address && s.address === serverAddress) {
                isTargetServer = true;
            }
            
            if (isTargetServer) {
                if (typeof s === 'string') {
                    // 如果是字符串，转换为对象
                    upstream.rawConfig.servers[i] = { server: s, enable: enabled };
                } else {
                    // 如果是对象，直接修改 enable 字段
                    upstream.rawConfig.servers[i].enable = enabled;
                }
                break;
            }
        }
    }

    // 从配置更新upstream数据
    updateUpstreamFromConfig(upstream, config) {
        if (!config) return;

        // 更新 rawConfig
        upstream.rawConfig = { ...config };
        // 更新前端显示数据
        upstream.enable = config.enable !== false;
        // 更新服务器列表
        upstream.servers = this.parseServersFromConfig(config.servers);

        // 保存到 localStorage
        this.saveDataToStorage();
    }

    // ESC键处理
    handleEscKey() {
        if (this.showEditModal.value) {
            this.closeEditModal();
        } else if (this.showDeleteServerModal.value) {
            this.closeDeleteServerModal();
        } else if (this.showConfModal.value) {
            this.closeShowConfModal();
        } else if (this.showHealthCheckerModal.value) {
            this.closeHealthCheckerModal();
        } else if (this.showAddServerModal.value) {
            this.closeAddServerModal();
        }
    }
    
    // 清理资源
    cleanup() {
        this.stopStatusRefresh();
        this.data.value = [];
        localStorage.removeItem('RestyPanel_upstreamsData');
        this.closeEditModal();
        this.closeShowConfModal();
        this.closeHealthCheckerModal();
        this.closeAddServerModal();
        this.closeDropdowns();
    }
    
    // 打开编辑模态框
    openEditModal(upstreamName) {
        const upstream = this.data.value.find(u => u.name === upstreamName);
        if (!upstream) return;
        
        this.editingUpstream.value = upstream;
        this.editingConfigText.value = JSON.stringify(upstream.rawConfig, null, 2);
        this.editError.value = '';
        this.showEditModal.value = true;
    }
    
    // 打开添加模态框
    openAddModal() {
        this.editingUpstream.value = { name: '', rawConfig: { name: '', servers: [] } };
        this.editingConfigText.value = JSON.stringify({ name: '', servers: [] }, null, 2);
        this.editError.value = '';
        this.showEditModal.value = true;
    }
    
    // 关闭编辑模态框
    closeEditModal() {
        this.showEditModal.value = false;
        this.editingUpstream.value = null;
        this.editingConfigText.value = '';
        this.editError.value = '';
        this.isSaving.value = false;
    }
    
    // 保存upstream配置
    async saveUpstreamConfig() {
        try {
            this.isSaving.value = true;
            this.editError.value = '';
            
            // 解析JSON配置
            let newConfig;
            try {
                newConfig = JSON.parse(this.editingConfigText.value);
            } catch (error) {
                this.editError.value = 'Invalid JSON format: ' + error.message;
                return;
            }
            
            // 验证必要字段
            if (!newConfig.name) {
                this.editError.value = 'Upstream name is required';
                return;
            }
            
            const isEditing = this.editingUpstream.value.name;
            
            // 如果是编辑模式，验证名称不能改变
            if (isEditing && newConfig.name !== this.editingUpstream.value.name) {
                this.editError.value = 'Cannot change upstream name';
                return;
            }
            
            // 如果是添加模式，检查名称是否已存在
            if (!isEditing && this.data.value.find(u => u.name === newConfig.name)) {
                this.editError.value = 'Upstream name already exists';
                return;
            }
            
            // 调用API
            let resp;
            if (isEditing) {
                // 编辑现有upstream
                resp = await ApiService.upstreams.update(this.editingUpstream.value.name, newConfig);
            } else {
                // 添加新upstream
                resp = await ApiService.upstreams.create(newConfig);
            }
            if (!resp || resp.code !== 200) {
                // 显示错误通知
                if (window.showNotification) {
                    window.showNotification('error', resp?.message || 'Failed to save upstream configuration');
                }
                this.editError.value = resp?.message || 'Failed to save configuration';
                return;
            }
            
            // 使用返回的数据更新内存中的配置
            const returnedConfig = resp.data;
            if (returnedConfig) {
                if (isEditing) {
                    // 编辑模式：更新现有的 upstream
                    const existingIndex = this.data.value.findIndex(u => u.name === this.editingUpstream.value.name);
                    if (existingIndex !== -1) {
                        this.updateUpstreamFromConfig(this.data.value[existingIndex], returnedConfig);
                    }
                } else {
                    // 添加模式：添加新的 upstream
                    const newUpstream = {
                        rawConfig: { ...returnedConfig },
                        name: returnedConfig.name,
                        enable: returnedConfig.enable !== false,
                        servers: this.parseServersFromConfig(returnedConfig.servers),
                        hasCheckers: true,
                        isToggling: false
                    };
                    this.data.value.push(newUpstream);
                    this.saveDataToStorage();
                }
            }
            
            // 关闭模态框
            this.closeEditModal();
            // 重新拉取状态
            await this.updateUpstreamStatus();
            // 显示成功通知
            if (window.showNotification) {
                const action = isEditing ? 'updated' : 'created';
                window.showNotification('success', `Upstream "${newConfig.name}" ${action} successfully`);
            }
        } catch (err) {
            console.error('Error saving upstream config:', err);
            this.editError.value = err.message || 'Failed to save configuration';
            // 显示错误通知
            if (window.showNotification) {
                window.showNotification('error', err?.message || 'Failed to save upstream configuration');
            }
        } finally {
            this.isSaving.value = false;
        }
    }
    
    // 删除操作前确认
    confirmDelete(upstreamName) {
        window.NotificationManager.confirm({
            title: '删除 Upstream',
            message: `确定要删除 upstream <b>${upstreamName}</b> 吗？<br>此操作无法撤销。`,
            confirmText: '删除',
            cancelText: '取消',
            dangerStyle: true,
            onConfirm: async () => {
                await this.deleteUpstream(upstreamName);
            }
        });
    }
    
    // 删除upstream
    async deleteUpstream(upstreamName) {
        try {
            // 调用删除API
            const resp = await ApiService.upstreams.delete(upstreamName);
            if (!resp || resp.code !== 200) {
                // 显示错误通知
                if (window.showNotification) {
                    window.showNotification('error', resp?.message || 'Failed to delete upstream');
                }
                return;
            }
            // 显示成功通知
            if (window.showNotification) {
                window.showNotification('success', `Upstream "${upstreamName}" deleted successfully`);
            }
            // 重新获取upstream列表
            await this.fetchUpstreams();
            // 重新拉取状态
            await this.updateUpstreamStatus();
        } catch (err) {
            console.error('Error deleting upstream:', err);
            // 显示错误通知
            if (window.showNotification) {
                window.showNotification('error', err?.message || 'Failed to delete upstream');
            }
        }
    }
    
    // 打开 upstream.conf 展示模态框
    async openShowConfModal() {
        this.showConfModal.value = true;
        this.upstreamConfContent.value = '';
        this.confError.value = '';
        try {
            const resp = await ApiService.upstreams.showConf();
            this.upstreamConfContent.value = resp.data.content;
            
            // 在下一个 tick 初始化 CodeMirror
            Vue.nextTick(() => this.initConfViewer());
        } catch (err) {
            this.confError.value = err.message || 'Failed to load upstream.conf';
            if (window.showNotification) {
                window.showNotification('error', this.confError.value);
            }
        }
    }
    
    // 初始化 CodeMirror 查看器
    initConfViewer() {
        const viewerDiv = document.getElementById('upstream-config-viewer');
        if (viewerDiv) {
            // 清除之前的实例
            viewerDiv.innerHTML = '';
            
            // 创建新的 CodeMirror 实例
            this.confViewerInstance = CodeMirror(viewerDiv, {
                value: this.upstreamConfContent.value || '',
                mode: 'nginx',
                theme: 'dracula',
                lineNumbers: true,
                readOnly: true,
                lineWrapping: true
            });
        }
    }
    
    // 关闭 upstream.conf 展示模态框
    closeShowConfModal() {
        this.showConfModal.value = false;
        this.upstreamConfContent.value = '';
        this.confError.value = '';
        
        // 清理 CodeMirror 实例
        if (this.confViewerInstance) {
            this.confViewerInstance = null;
        }
    }
    // 打开健康检查模态框
    openHealthCheckerModal(upstreamName) {
        function getOrDefault(val, def) {
            return val === undefined || val === null || val === '' ? def : val;
        }
        
        this.healthCheckerError.value = '';
        this.showHealthCheckerModal.value = true;
        
        // 获取当前 upstream 的 health_check 配置或默认值
        const upstream = this.data.value.find(u => u.name === upstreamName);
        const hc = (upstream && upstream.rawConfig && upstream.rawConfig.health_check) || {};
        
        // 直接重新赋值整个对象，确保 Vue 能够检测到变化
        Object.assign(this.healthCheckerForm, {
            type: getOrDefault(hc.type, 'http'),
            http_req: getOrDefault(hc.http_req, 'GET /status HTTP/1.0\r\nHost: foo.com\r\n\r\n'),
            port: getOrDefault(hc.port, ''),
            interval: getOrDefault(hc.interval, 6000),
            timeout: getOrDefault(hc.timeout, 3000),
            fall: getOrDefault(hc.fall, 1),
            rise: getOrDefault(hc.rise, 1),
            valid_statuses: getOrDefault(hc.valid_statuses && hc.valid_statuses.length > 0 ? hc.valid_statuses.join(',') : '', '200,302'),
            concurrency: getOrDefault(hc.concurrency, 10),
            ssl_verify: getOrDefault(hc.ssl_verify, false),
            host: getOrDefault(hc.host, '')
        });
        
        // 存储当前编辑的 upstream 名称
        this.currentEditingUpstream = upstreamName;
    }
    // 关闭健康检查模态框
    closeHealthCheckerModal() {
        this.showHealthCheckerModal.value = false;
        this.currentEditingUpstream = null;
        this.healthCheckerError.value = '';
    }
    // 保存健康检查配置
    async saveHealthChecker() {
        const name = this.currentEditingUpstream;
        const upstream = this.data.value.find(u => u.name === name);
        if (!upstream) return;
        this.healthCheckerError.value = '';
        // 构造 health_check 字段
        const form = this.healthCheckerForm;
        let valid_statuses = form.valid_statuses;
        if (typeof valid_statuses === 'string') {
            valid_statuses = valid_statuses.split(',').map(s => parseInt(s.trim())).filter(n => !isNaN(n));
        }
        const health_check = {
            type: form.type,
            http_req: form.http_req,
            port: form.port !== '' && form.port !== null && form.port !== undefined ? parseInt(form.port) : undefined,
            interval: form.interval !== '' && form.interval !== null && form.interval !== undefined ? parseInt(form.interval) : 2000,
            timeout: form.timeout !== '' && form.timeout !== null && form.timeout !== undefined ? parseInt(form.timeout) : 1000,
            fall: form.fall !== '' && form.fall !== null && form.fall !== undefined ? parseInt(form.fall) : 3,
            rise: form.rise !== '' && form.rise !== null && form.rise !== undefined ? parseInt(form.rise) : 2,
            valid_statuses,
            concurrency: form.concurrency !== '' && form.concurrency !== null && form.concurrency !== undefined ? parseInt(form.concurrency) : 10
        };
        // 仅 https 时写入 ssl_verify/host
        if (form.type === 'https') {
            health_check.ssl_verify = !!form.ssl_verify;
            if (form.host && form.host.trim() !== '') {
                health_check.host = form.host;
            }
        }
        // 清理 undefined/null/空字符串字段
        Object.keys(health_check).forEach(k => {
            if (health_check[k] === undefined || health_check[k] === null || health_check[k] === '') {
                delete health_check[k];
            }
        });
        // 写入 rawConfig
        upstream.rawConfig.health_check = health_check;
        try {
            const resp = await ApiService.upstreams.update(name, upstream.rawConfig);
            
            // 使用返回的数据更新内存中的配置
            const returnedConfig = resp.data;
            // 更新 rawConfig
            upstream.rawConfig = { ...returnedConfig };
            // 更新前端显示数据
            upstream.enable = returnedConfig.enable !== false;
            // 更新服务器列表
            upstream.servers = (returnedConfig.servers || []).map(s => {
                let address = '';
                let weight;
                let enable = true;
                
                if (typeof s === 'string') {
                    address = s;
                } else {
                    if (s.server) address = s.server;
                    else if (s.host) address = s.port ? `${s.host}:${s.port}` : s.host;
                    else if (s.address) address = s.address;
                    weight = s.weight;
                    enable = s.enable !== false;
                }
                
                return { 
                    address, 
                    weight, 
                    status: 'UNKNOWN',
                    enable,
                    isToggling: false
                };
            });
            
            // 保存到 localStorage
            localStorage.setItem('RestyPanel_upstreamsData', JSON.stringify(this.data.value));
            
            if (window.showNotification) window.showNotification('success', 'Health checker saved');
            this.closeHealthCheckerModal();
            await this.updateUpstreamStatus();
        } catch (err) {
            this.healthCheckerError.value = err.message || 'Failed to save health checker';
            if (window.showNotification) window.showNotification('error', this.healthCheckerError.value);
        }
    }

    // Dropdown and Add Server Modal methods
    toggleDropdown(upstreamName) {
        if (this.activeDropdown.value === upstreamName) {
            this.activeDropdown.value = null;
        } else {
            this.activeDropdown.value = upstreamName;
        }
    }

    closeDropdowns() {
        this.activeDropdown.value = null;
    }

    openAddServerModal(upstreamName) {
        this.currentUpstreamForAddServer.value = upstreamName;
        this.addServerForm.value = { address: '', weight: 1 };
        this.addServerError.value = '';
        this.activeDropdown.value = null; // Close dropdown
        this.showAddServerModal.value = true;
    }

    closeAddServerModal() {
        this.showAddServerModal.value = false;
        this.currentUpstreamForAddServer.value = null;
        this.addServerError.value = '';
    }

    async saveNewServer() {
        const upstreamName = this.currentUpstreamForAddServer.value;
        const form = this.addServerForm.value;

        if (!form.address || !form.address.trim()) {
            this.addServerError.value = 'Server address is required.';
            return;
        }

        const upstream = this.data.value.find(u => u.name === upstreamName);
        if (!upstream) {
            this.addServerError.value = 'Upstream not found.';
            return;
        }

        // Initialize rawConfig if it doesn't exist
        if (!upstream.rawConfig) {
            upstream.rawConfig = { name: upstreamName };
        }

        // Initialize servers array if it doesn't exist
        if (!upstream.rawConfig.servers) {
            upstream.rawConfig.servers = [];
        }

        // Extra safety checks for server entries
        let serverExists = false;
        try {
            serverExists = Array.isArray(upstream.rawConfig.servers) && 
                upstream.rawConfig.servers.some(s => {
                    if (!s) return false; // Skip null/undefined entries
                    const serverAddress = (typeof s === 'string') ? s : (s.server || '');
                    return serverAddress === form.address.trim();
                });
        } catch (err) {
            console.error('Error checking for existing servers:', err);
            // Initialize as empty array if there was an error
            upstream.rawConfig.servers = [];
        }

        if (serverExists) {
            this.addServerError.value = 'Server with this address already exists in the upstream.';
            return;
        }

        const newServer = {
            server: form.address.trim()
        };
        if (form.weight && parseInt(form.weight, 10) > 0) {
            newServer.weight = parseInt(form.weight, 10);
        }
        
        upstream.rawConfig.servers.push(newServer);

        this.isSaving.value = true;
        this.addServerError.value = '';

        try {
            const resp = await ApiService.upstreams.update(upstreamName, upstream.rawConfig);
            if (!resp || resp.code !== 200) {
                upstream.rawConfig.servers.pop(); // Revert on failure
                this.addServerError.value = resp?.message || 'Failed to add server.';
                if (window.showNotification) window.showNotification('error', this.addServerError.value);
            } else {
                if (window.showNotification) window.showNotification('success', 'Server added successfully.');
                this.closeAddServerModal();
                await this.fetchUpstreams();
                await this.updateUpstreamStatus();
            }
        } catch (err) {
            upstream.rawConfig.servers.pop(); // Revert on failure
            this.addServerError.value = err.message || 'An unexpected error occurred.';
            if (window.showNotification) window.showNotification('error', this.addServerError.value);
        } finally {
            this.isSaving.value = false;
        }
    }

    confirmDeleteServer(upstreamName, serverAddress) {
        window.NotificationManager.confirm({
            title: '删除 Server',
            message: `确定要删除服务器 <b>${serverAddress}</b> <br>从 upstream <b>${upstreamName}</b> 吗？<br>此操作无法撤销。`,
            confirmText: '删除',
            cancelText: '取消',
            dangerStyle: true,
            onConfirm: async () => {
                const upstream = this.data.value.find(u => u.name === upstreamName);
                if (!upstream) {
                    if (window.showNotification) window.showNotification('error', `Upstream not found`);
                    return;
                }

                const serverIndex = upstream.rawConfig.servers.findIndex(s => {
                    const currentAddress = (typeof s === 'string') ? s : s.server;
                    return currentAddress === serverAddress;
                });

                if (serverIndex === -1) {
                    if (window.showNotification) window.showNotification('error', `Server not found`);
                    return;
                }

                const removedServer = upstream.rawConfig.servers[serverIndex];
                upstream.rawConfig.servers.splice(serverIndex, 1);

                try {
                    const resp = await ApiService.upstreams.update(upstreamName, upstream.rawConfig);
                    if (!resp || resp.code !== 200) {
                        upstream.rawConfig.servers.splice(serverIndex, 0, removedServer);
                        if (window.showNotification) window.showNotification('error', resp?.message || 'Failed to delete server');
                        return;
                    }
                    if (window.showNotification) window.showNotification('success', 'Server deleted successfully');
                    await this.fetchUpstreams();
                    await this.updateUpstreamStatus();
                } catch (err) {
                    upstream.rawConfig.servers.splice(serverIndex, 0, removedServer);
                    if (window.showNotification) window.showNotification('error', err.message || 'Failed to delete server');
                }
            }
        });
    }
}

// 创建全局UpstreamsManager类
window.UpstreamsManager = UpstreamsManager; 