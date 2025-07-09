// RestyPanel Management Interface - 主应用文件

// 创建Vue应用
const { createApp, ref, reactive, computed, onMounted, onUnmounted, nextTick } = Vue;

const app = createApp({
    setup() {
        // 响应式数据
        const isAuthenticated = ref(false);
        const isLoading = ref(false);
        const error = ref('');
        const currentPage = ref(localStorage.getItem('RestyPanel_currentPage') || 'status');
        const sidebarCollapsed = ref(false);
        const logsSubmenuOpen = ref(false); // 添加日志子菜单状态
        
        // 用户信息
        const user = ref({ username: '' });
        
        // 登录表单
        const loginForm = reactive({
            username: 'RestyPanel',
            password: 'RestyPanel'
        });
        
        // Status 页面数据
        const statusData = ref({});
        const autoRefresh = ref(true);
        const refreshInterval = ref(3);
        const timeWindow = ref(300); // 默认5分钟
        const isRefreshing = ref(false);
        
        // Upstreams 页面数据
        const upstreamsManager = new UpstreamsManager();
        
        // Servers 页面数据
        const serversManager = ServersManager;
        
        // Status 管理器实例
        let statusManager = null;
        
        // 通知队列集成
        const notifications = NotificationManager.notifications;
        const confirmDialog = NotificationManager.confirmDialog;
        const showNotification = NotificationManager.show;
        const hideNotification = NotificationManager.clear;
        const showConfirmDialog = NotificationManager.confirm;
        
        // 计算属性
        const avgResponseTime = computed(() => {
            const total = statusData.value.response_time_total || 0;
            const count = statusData.value.request_all_count || 1;
            return ((total / count) * 1000).toFixed(2);
        });
        
        // 工具函数
        const formatBytes = (bytes) => {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        };
        
        // 启动时间格式化
        const formatBootTime = (bootTime) => {
            if (!bootTime) return '--';
            const date = new Date(bootTime * 1000);
            return date.toLocaleString();
        };
        
        // 启动时长格式化
        const formatUptime = (bootTime) => {
            if (!bootTime) return '--';
            const now = Math.floor(Date.now() / 1000);
            let seconds = now - bootTime;
            if (seconds < 60) return `${seconds} S`;
            const mins = seconds / 60;
            if (mins < 60) return `${mins.toFixed(1)} Mins`;
            const hours = mins / 60;
            if (hours < 24) return `${hours.toFixed(1)} Hours`;
            const days = hours / 24;
            return `${days.toFixed(1)} Days`;
        };
        
        // 最后更新时间格式化
        const formatLastUpdateTime = (date) => {
            if (!date) return '';
            return date.toLocaleString();
        };
        
        // 认证相关方法
        const checkAuth = async () => {
            const token = localStorage.getItem('RestyPanel_token');
            if (!token) {
                console.log('No token found');
                return false;
            }
            
            // 检查token是否有效（未过期）
            if (TokenManager.isValidToken()) {
                console.log('Token is valid');
                return true;
            } else {
                console.log('Token is invalid or expired');
                localStorage.removeItem('RestyPanel_token');
                return false;
            }
        };
        
        const handleLogin = async () => {
            if (isLoading.value) return;
            
            isLoading.value = true;
            error.value = '';
            
            try {
                const response = await ApiService.auth.login({
                    username: loginForm.username,
                    password: loginForm.password
                });
                
                console.log('Login response:', response);
                
                if (response.code === 200 && response.data.access_token) {
                    // 使用TokenManager来正确设置token（包括axios请求头）
                    TokenManager.setToken(response.data.access_token);
                    
                    // 设置用户信息（从响应中获取）
                    user.value.username = response.data.user?.id || loginForm.username;
                    isAuthenticated.value = true;
                    
                    console.log('Login successful, user:', user.value.username);
                    console.log('Token type:', response.data.token_type);
                    console.log('Expires in:', response.data.expires_in, 'seconds');
                    
                    // 登录成功后初始化
                    await nextTick();
                    setTimeout(() => {
                        if (currentPage.value === 'status') {
                            initStatusPage();
                        }
                    }, 300);
                } else {
                    error.value = response.message || 'Login failed';
                }
            } catch (err) {
                console.error('Login error details:', err);
                if (err.response) {
                    error.value = err.response.data?.message || `Server error: ${err.response.status}`;
                } else if (err.request) {
                    error.value = 'Network error: Unable to connect to server';
                } else {
                    error.value = 'Login failed: ' + err.message;
                }
            } finally {
                isLoading.value = false;
            }
        };
        
        const logout = async () => {
            try {
                await ApiService.auth.logout();
            } catch (error) {
                console.error('Logout error:', error);
            } finally {
                TokenManager.removeToken();
                isAuthenticated.value = false;
                user.value = { username: '' };
                currentPage.value = 'status';
                cleanupStatusPage();
                localStorage.removeItem('RestyPanel_currentPage');
                localStorage.removeItem('RestyPanel_upstreamsData');
            }
        };
        
        // Status 页面相关方法
        const initStatusPage = () => {
            console.log('Initializing status page...');
            
            if (!statusManager) {
                statusManager = new StatusManager();
            }
            
            // 设置时间窗口
            statusManager.setTimeWindow(parseInt(timeWindow.value));
            
            // 初始化图表
            statusManager.initCharts();
            
            // 如果开启自动刷新，启动刷新
            if (autoRefresh.value) {
                statusManager.startAutoRefresh(parseInt(refreshInterval.value));
            }
            
            // 监听状态数据变化
            const updateStatusData = () => {
                statusData.value = statusManager.getCurrentData();
            };
            
            // 每次刷新后更新状态数据
            const originalFetchStatus = statusManager.fetchStatus;
            statusManager.fetchStatus = async function() {
                isRefreshing.value = true;
                try {
                    const result = await originalFetchStatus.call(this);
                    statusData.value = result;
                    return result;
                } catch (error) {
                    console.error('Error in status fetch:', error);
                    throw error;
                } finally {
                    isRefreshing.value = false;
                }
            };
        };
        
        const cleanupStatusPage = () => {
            if (statusManager) {
                statusManager.cleanup();
                statusManager = null;
            }
        };
        
        const refreshStatus = () => {
            if (statusManager && !isRefreshing.value) {
                console.log('Manual refresh triggered');
                statusManager.manualRefresh();
            }
        };
        
        const toggleAutoRefresh = () => {
            if (!statusManager) return;
            
            if (autoRefresh.value) {
                statusManager.startAutoRefresh(parseInt(refreshInterval.value));
            } else {
                statusManager.stopAutoRefresh();
            }
        };
        
        const updateRefreshInterval = () => {
            if (!statusManager) return;
            
            console.log('Refresh interval changed to:', refreshInterval.value, 'seconds');
            statusManager.updateRefreshInterval(parseInt(refreshInterval.value));
        };
        
        const updateTimeWindow = () => {
            if (!statusManager) return;
            
            console.log('Time window changed to:', timeWindow.value, 'seconds');
            statusManager.setTimeWindow(parseInt(timeWindow.value));
        };
        
        // 页面切换处理
        const handlePageChange = async (newPage) => {
            console.log('Changing page to:', newPage);
            currentPage.value = newPage;
            localStorage.setItem('RestyPanel_currentPage', newPage);
            
            // 如果切换到状态页，初始化图表
            if (newPage === 'status') {
                cleanupStatusPage();
                await nextTick();
                initStatusPage();
            } 
            // 如果切换到上游页，加载上游数据
            else if (newPage === 'upstreams') {
                if (!upstreamsManager.data.value.length) {
                    upstreamsManager.updateUpstreamStatus();
                }
            }
            // 如果切换到服务器页，加载服务器数据
            else if (newPage === 'servers') {
                serversManager.refreshServerList();
            }
            // 如果切换到日志页，加载日志文件列表
            else if (newPage === 'logs') {
                logsManager.fetchLogFiles();
            }
            // 如果切换到报告页，加载报告列表
            else if (newPage === 'reports') {
                logsManager.fetchReports();
            }
            // 如果切换到设置页，加载路径设置
            else if (newPage === 'settings') {
                loadPathSettings();
            }
            
            // 如果在移动设备上，切换页面后关闭侧边栏
            if (window.innerWidth < 768) {
                closeSidebar();
            }
        };
        
        // 切换日志子菜单
        const toggleLogsSubmenu = () => {
            logsSubmenuOpen.value = !logsSubmenuOpen.value;
            if (logsSubmenuOpen.value && currentPage.value !== 'logs' && currentPage.value !== 'reports') {
                handlePageChange('logs');
            }
        };
        
        // 侧边栏切换
        const toggleSidebar = () => {
            sidebarCollapsed.value = !sidebarCollapsed.value;
        };
        
        const closeSidebar = () => {
            if (window.innerWidth <= 768) {
                sidebarCollapsed.value = true;
            }
        };
        
        // 获取页面标题
        const getPageTitle = () => {
            const titles = {
                status: 'System Status Monitor',
                upstreams: 'Upstream Management',
                servers: 'Server Management', 
                waf: 'Web Application Firewall',
                logs: 'Log Analysis',
                settings: 'System Settings'
            };
            return titles[currentPage.value] || 'Dashboard';
        };
        
        // 全局 Esc 键处理函数
        const handleEscKey = (event) => {
            if (event.key === 'Escape' || event.keyCode === 27) {
                // 检查并关闭所有打开的模态框
                if (upstreamsManager.showEditModal.value) {
                    upstreamsManager.closeEditModal();
                } else if (upstreamsManager.showDeleteModal.value) {
                    upstreamsManager.closeDeleteModal();
                } else if (upstreamsManager.showConfModal.value) {
                    upstreamsManager.closeShowConfModal();
                } else if (upstreamsManager.showHealthCheckerModal.value) {
                    upstreamsManager.closeHealthCheckerModal();
                } else if (serversManager.showEditModal.value) {
                    serversManager.closeEditModal();
                } else if (serversManager.showViewModal.value) {
                    serversManager.closeViewModal();
                } else if (serversManager.showDeleteModal.value) {
                    serversManager.closeDeleteModal();
                } else if (logsManager.showReportModal.value) {
                    logsManager.closeReportModal();
                } else if (logsManager.showDeleteAllConfirmModal.value) {
                    logsManager.closeDeleteAllConfirmModal();
                }
            }
        };

        // 全局 click 监听器，用于关闭下拉菜单
        const closeAllDropdowns = () => {
            if (upstreamsManager.activeDropdown.value) {
                upstreamsManager.closeDropdowns();
            }
            // 未来可以添加其他管理器的下拉菜单关闭逻辑
        };
        
        // 生命周期
        onMounted(async () => {
            console.log('App mounted, checking authentication...');
            
            // 检查屏幕尺寸，移动端默认折叠侧边栏
            if (window.innerWidth <= 768) {
                sidebarCollapsed.value = true;
            }
            
            const authenticated = await checkAuth();
            isAuthenticated.value = authenticated;
            
            if (authenticated) {
                console.log('User is authenticated');
                
                // 从token中获取用户信息
                try {
                    const token = localStorage.getItem('RestyPanel_token');
                    if (token) {
                        const payload = JSON.parse(atob(token.split('.')[1]));
                        user.value.username = payload.sub || 'User';
                        console.log('User info from token:', user.value.username);
                    } else {
                        user.value.username = 'User';
                    }
                } catch (error) {
                    console.log('Unable to parse token for user info, using default username');
                    user.value.username = 'User';
                }
                
                console.log('User info set:', user.value.username);
                
                
                // Initialize the correct page based on the value from localStorage
                if (currentPage.value === 'status') {
                    await nextTick();
                    initStatusPage();
                } else if (currentPage.value === 'upstreams') {
                    await nextTick();
                    // The page will initially render with stale data from localStorage,
                    // then fetch fresh data.
                    upstreamsManager.fetchUpstreams().then(async () => {
                        await upstreamsManager.updateUpstreamStatus();
                    });
                } else if (currentPage.value === 'servers') {
                    await nextTick();
                    serversManager.init();
                } else if (currentPage.value === 'logs' || currentPage.value === 'reports') {
                    await nextTick();
                    logsManager.init();
                }
            } else {
                console.log('User is not authenticated');
            }
            
            // 监听窗口大小变化
            window.addEventListener('resize', () => {
                if (window.innerWidth <= 768) {
                    sidebarCollapsed.value = true;
                } else {
                    sidebarCollapsed.value = false;
                }
            });
            
            // 添加键盘事件监听器
            document.addEventListener('keydown', handleEscKey);

            // 添加全局点击监听器
            window.addEventListener('click', (e) => {
                if (!e.target.closest('.dropdown')) {
                    closeAllDropdowns();
                }
            });
            
            // 暴露通知函数到全局
            window.showNotification = showNotification;
            window.hideNotification = hideNotification;
        });
        
        onUnmounted(() => {
            cleanupStatusPage();
            upstreamsManager.cleanup();
            // 移除键盘事件监听器
            document.removeEventListener('keydown', handleEscKey);
            // 移除全局点击监听器
            window.removeEventListener('click', closeAllDropdowns);
        });
        
        // 返回响应式数据和方法
        return {
            // 认证状态
            isAuthenticated,
            loginForm,
            isLoading,
            error,
            handleLogin,
            logout,
            user,
            
            // 页面状态
            currentPage,
            handlePageChange,
            sidebarCollapsed,
            toggleSidebar,
            closeSidebar,
            getPageTitle,
            
            // 日志子菜单
            logsSubmenuOpen,
            toggleLogsSubmenu,
            
            // Status 页面状态
            statusData,
            autoRefresh,
            refreshInterval,
            timeWindow,
            isRefreshing,
            formatBytes,
            formatBootTime,
            formatUptime,
            formatLastUpdateTime,
            avgResponseTime,
            refreshStatus,
            toggleAutoRefresh,
            updateRefreshInterval,
            updateTimeWindow,
            
            // 通知系统
            notifications,
            showNotification,
            hideNotification,
            showConfirmDialog,
            confirmDialog,
            
            // 模块管理器
            upstreamsManager,
            serversManager,
            logsManager,
            
            // 路径设置
            pathSettings: ref({
                logs_dir: '/var/log/nginx/',
                reports_dir: '/app/web/reports/'
            }),
            pathSettingsError: ref(null),
            isSavingPaths: ref(false),
            
            // 方法
            loadPathSettings() {
                ApiService.settings.getPaths()
                    .then(response => {
                        if (response && response.data && response.data.code === 200) {
                            this.pathSettings = response.data.data || {
                                logs_dir: '/var/log/nginx/',
                                reports_dir: '/app/web/reports/'
                            };
                            console.log('Loaded path settings:', this.pathSettings);
                        } else {
                            console.warn('Invalid response format for path settings', response);
                            // Use defaults if response is invalid
                            this.pathSettings = {
                                logs_dir: '/var/log/nginx/',
                                reports_dir: '/app/web/reports/'
                            };
                        }
                    })
                    .catch(error => {
                        console.error('Failed to load path settings:', error);
                        showNotification('Error loading path settings', 'error');
                        // Use defaults on error
                        this.pathSettings = {
                            logs_dir: '/var/log/nginx/',
                            reports_dir: '/app/web/reports/'
                        };
                    });
            },
            
            savePathSettings() {
                this.isSavingPaths = true;
                this.pathSettingsError = null;
                
                ApiService.settings.updatePaths(this.pathSettings)
                    .then(response => {
                        showNotification('Path settings saved successfully', 'success');
                        this.pathSettings = response.data;
                        
                        // 重新加载日志和报告，以应用新路径
                        if (currentPage.value === 'logs') {
                            logsManager.fetchLogFiles();
                        } else if (currentPage.value === 'reports') {
                            logsManager.fetchReports();
                        }
                    })
                    .catch(error => {
                        console.error('Failed to save path settings:', error);
                        this.pathSettingsError = error.response?.data?.message || 'Failed to save path settings';
                        showNotification('Error saving path settings', 'error');
                    })
                    .finally(() => {
                        this.isSavingPaths = false;
                    });
            },
            
            // 页面切换
            handlePageChange,
            
            // 切换日志子菜单
            toggleLogsSubmenu,
            
            // 侧边栏切换
            toggleSidebar,
            closeSidebar,
            
            // 获取页面标题
            getPageTitle,
            
            // 通知系统
            notifications,
            showNotification,
            hideNotification,
            showConfirmDialog,
            confirmDialog,
            
            // 全局窗口引用
            window,
        };
    },
});

// 挂载Vue应用
app.mount('#app');

// 全局错误处理
window.addEventListener('unhandledrejection', event => {
    console.error('Unhandled promise rejection:', event.reason);
});

// 页面加载完成提示
console.log('loaded successfully'); 