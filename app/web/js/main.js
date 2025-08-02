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
            password: '1'
        });

        // 创建管理器实例
        const upstreamsManager = new UpstreamsManager();
        const serversManager = new ServersManager();
        const statusManager = new StatusManager();
        const logsManager = new LogsManager();

        // 路径设置
        const pathSettings = ref({
            logs_dir: '/var/log/nginx/',
            reports_dir: '/app/web/reports/'
        });
        const pathSettingsError = ref(null);
        const isSavingPaths = ref(false);

        // 通知队列集成
        const notifications = NotificationManager.notifications;
        const confirmDialog = NotificationManager.confirmDialog;
        const showNotification = NotificationManager.show;
        const hideNotification = NotificationManager.clear;
        const showConfirmDialog = NotificationManager.confirm;

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
                    handlePageChange(currentPage.value);
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
                // 清理所有管理器
                statusManager.cleanup();
                upstreamsManager.cleanup();
                serversManager.cleanup();
                logsManager.cleanup();
                localStorage.removeItem('RestyPanel_currentPage');
                localStorage.removeItem('RestyPanel_upstreamsData');
            }
        };

        // 页面切换处理
        const handlePageChange = async (newPage) => {
            console.log('Changing page to:', newPage);

            // 更新当前页面
            currentPage.value = newPage;
            localStorage.setItem('RestyPanel_currentPage', newPage);

            // 根据页面类型调用对应管理器的初始化方法
            // 停止自动刷新
            upstreamsManager.stopStatusRefresh();
            statusManager.stopAutoRefresh();
            await nextTick();
            switch (newPage) {
                case 'status':
                    statusManager.initStatusPage();
                    break;
                case 'upstreams':
                    upstreamsManager.init();
                    break;
                case 'servers':
                    serversManager.init();
                    break;
                case 'logs':
                    logsManager.fetchLogFiles();
                    break;
                case 'reports':
                    logsManager.fetchReports();
                    break;
                case 'settings':
                    loadPathSettings();
                    break;
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
                // 调用各管理器的模态框关闭方法
                upstreamsManager.handleEscKey();
                serversManager.handleEscKey();
                logsManager.handleEscKey();
            }
        };

        // 全局 click 监听器，用于关闭下拉菜单
        const closeAllDropdowns = () => {
            upstreamsManager.closeDropdowns();
            serversManager.closeDropdowns();
            logsManager.closeDropdowns();
        };

        // 路径设置加载方法
        const loadPathSettings = () => {
            ApiService.settings.getPaths()
                .then(response => {
                    if (response && response.data && response.data.code === 200) {
                        pathSettings.value = response.data.data || {
                            logs_dir: '/var/log/nginx/',
                            reports_dir: '/app/web/reports/'
                        };
                        console.log('Loaded path settings:', pathSettings.value);
                    } else {
                        console.warn('Invalid response format for path settings', response);
                        // Use defaults if response is invalid
                        pathSettings.value = {
                            logs_dir: '/var/log/nginx/',
                            reports_dir: '/app/web/reports/'
                        };
                    }
                })
                .catch(error => {
                    console.error('Failed to load path settings:', error);
                    showNotification('Error loading path settings', 'error');
                    // Use defaults on error
                    pathSettings.value = {
                        logs_dir: '/var/log/nginx/',
                        reports_dir: '/app/web/reports/'
                    };
                });
        };

        // 保存路径设置
        const savePathSettings = () => {
            isSavingPaths.value = true;
            pathSettingsError.value = null;

            ApiService.settings.updatePaths(pathSettings.value)
                .then(response => {
                    showNotification('Path settings saved successfully', 'success');
                    pathSettings.value = response.data;

                    // 重新加载日志和报告，以应用新路径
                    if (currentPage.value === 'logs') {
                        logsManager.fetchLogFiles();
                    } else if (currentPage.value === 'reports') {
                        logsManager.fetchReports();
                    }
                })
                .catch(error => {
                    console.error('Failed to save path settings:', error);
                    pathSettingsError.value = error.response?.data?.message || 'Failed to save path settings';
                    showNotification('Error saving path settings', 'error');
                })
                .finally(() => {
                    isSavingPaths.value = false;
                });
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

                // 初始化当前页面
                await handlePageChange(currentPage.value);
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
            // 清理所有管理器
            statusManager.cleanup();
            upstreamsManager.cleanup();
            serversManager.cleanup();
            logsManager.cleanup();

            // 移除事件监听器
            document.removeEventListener('keydown', handleEscKey);
            window.removeEventListener('click', closeAllDropdowns);
        });


        // 格式化工具方法    
        // 格式化字节
        const formatBytes = (bytes) => {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }

        // 启动时间格式化
        const formatBootTime = (bootTime) => {
            if (!bootTime) return '--';
            const date = new Date(bootTime * 1000);
            return date.toLocaleString();
        }

        // 启动时长格式化
        const formatUptime = (bootTime) => {
            if (!bootTime) return '--';
            const now = Math.floor(Date.now() / 1000);
            let seconds = now - bootTime;
            if (seconds < 60) return `${seconds} S`;
            const mins = Math.floor(seconds / 60);
            if (mins < 60) return `${mins} Mins`;
            const hours = Math.floor(mins / 60);
            if (hours < 24) return `${hours} Hours`;
            const days = Math.floor(hours / 24);
            return `${days} Days`;
        }

        // 最后更新时间格式化
        const formatLastUpdateTime = (date) => {
            if (!date) return '';
            return date.toLocaleString();
        }

        // 获取当前时间字符串
        const getCurrentTime = () => {
            return new Date().toTimeString().split(' ')[0];
        }

        // 添加一个调试函数，用于查看每次渲染时的数据
        const debugStatusData = () => {
            console.log('页面渲染时的 statusManager.statusData:', statusManager.statusData);
            console.log('页面渲染时的 statusManager.statusData.value:', statusManager.statusData.value);
            return '';
        };

        // 模态框覆盖层点击处理函数
        const handleOverlayClick = (event) => {
            // 只有当点击事件的目标是覆盖层本身时才关闭模态框
            // 这样可以防止拖动操作导致模态框关闭
            if (event.target === event.currentTarget) {
                // 仅当点击了模态框覆盖层本身时（不是在拖动过程中）才关闭相应的模态框
                if (serversManager.showEditModal.value) {
                    serversManager.closeEditModal();
                }
                if (upstreamsManager.showEditModal.value) {
                    upstreamsManager.closeEditModal();
                }
                if (upstreamsManager.showConfModal.value) {
                    upstreamsManager.closeShowConfModal();
                }
                if (upstreamsManager.showHealthCheckerModal.value) {
                    upstreamsManager.closeHealthCheckerModal();
                }
                if (upstreamsManager.showAddServerModal.value) {
                    upstreamsManager.closeAddServerModal();
                }
                if (logsManager.showReportModal.value) {
                    logsManager.closeAnalyzeModal();
                }
                if (confirmDialog.show) {
                    confirmDialog.cancel();
                }
            }
        };

        // 返回响应式数据和方法
        return {
            // 模态框覆盖层点击处理
            handleOverlayClick,

            // 调试函数
            debugStatusData,

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

            // 格式化方法 - 委托给StatusManager
            formatBytes,
            formatBootTime,
            formatUptime,
            formatLastUpdateTime,
            getCurrentTime,

            // 通知系统
            notifications,
            showNotification,
            hideNotification,
            showConfirmDialog,
            confirmDialog,

            // 模块管理器
            statusManager,
            upstreamsManager,
            serversManager,
            logsManager,

            // 路径设置
            pathSettings,
            pathSettingsError,
            isSavingPaths,
            loadPathSettings,
            savePathSettings,

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