/**
 * Servers Manager Module
 * 
 * 管理服务器配置的功能模块，包括：
 * - 列出所有服务器配置
 * - 查看服务器配置详情
 * - 创建新的服务器配置
 * - 编辑现有服务器配置
 * - 删除服务器配置
 * - 测试、启用、禁用服务器配置
 */

class ServersManager {
    constructor() {
    // 使用Vue的响应式API
        this.isLoading = Vue.ref(false);
        this.isSaving = Vue.ref(false);
        this.isTesting = Vue.ref(false);
        this.showTestButtonInModal = Vue.ref(false);
        this.lastUpdateTime = Vue.ref(null);
        this.servers = Vue.ref([]);
        // 使用普通对象而不是ref对象，以便在HTML中直接访问
        this.summary = {
            total: 0,
            enabled: 0,
            disabled: 0,
            backup: 0
        };

        // 模态框状态
        this.showEditModal = Vue.ref(false);
        this.showViewModal = Vue.ref(false);
        this.showDeleteModal = Vue.ref(false);
        this.isEditing = Vue.ref(false);
        this.editError = Vue.ref('');
        this.deleteTarget = Vue.ref('');
        this.currentServer = Vue.ref(null);
        this.editorInstance = null;
        this.viewEditorInstance = null;

        // 编辑表单
        this.editForm = Vue.ref({
            name: '',
            content: ''
        });

        // New state for unified modal
        this.showSaveButton = Vue.ref(true);
        this.showTestButton = Vue.ref(false);
        this.showEnableButton = Vue.ref(false);
        this.showDisableButton = Vue.ref(false);
        this.isEditorReadOnly = Vue.ref(false);

        // 绑定方法上下文
        this.getModalTitle = this.getModalTitle.bind(this);
        this.refreshServerList = this.refreshServerList.bind(this);
        this.handleServerCardClick = this.handleServerCardClick.bind(this);
        this.initEditor = this.initEditor.bind(this);
        this.initViewEditor = this.initViewEditor.bind(this);
    }

    /**
     * 初始化模块
     */
    init() {
        console.log('Initializing servers manager...');
        this.refreshServerList();
    }

    /**
     * 刷新服务器列表
     */
    async refreshServerList() {
        try {
            this.isLoading.value = true;
            const response = await api.get('/servers');
            
            // 处理服务器列表数据
            if (response.data.data) {
                // 处理服务器列表
                if (response.data.data.items && Array.isArray(response.data.data.items)) {
                    // 确保每个服务器对象都有必要的属性
                    this.servers.value = response.data.data.items.map(server => ({
                        ...server,
                        isProcessing: false, // 添加处理状态属性
                        updated_at: server.updated_at ? new Date(server.updated_at * 1000) : new Date() // 转换时间戳为日期对象
                    }));
                } else {
                    console.warn('Server items missing or not an array in API response');
                    this.servers.value = [];
                }
                
                // 更新状态摘要
                if (response.data.data.status_summary) {
                    this.summary.total = response.data.data.status_summary.total || 0;
                    this.summary.enabled = response.data.data.status_summary.enabled || 0;
                    this.summary.disabled = response.data.data.status_summary.disabled || 0;
                    this.summary.backup = response.data.data.status_summary.backup || 0;
                } else {
                    // 手动计算状态摘要
                    let enabled = 0, disabled = 0, backup = 0;
                    this.servers.value.forEach(server => {
                        if (server.status === 'enabled') enabled++;
                        else if (server.status === 'disabled') disabled++;
                        else if (server.status === 'backup') backup++;
                    });
                    
                    this.summary.total = this.servers.value.length;
                    this.summary.enabled = enabled;
                    this.summary.disabled = disabled;
                    this.summary.backup = backup;
                }
                
                this.lastUpdateTime.value = new Date();
            } else {
                console.warn('Data missing in API response');
                this.servers.value = [];
                this.summary.total = 0;
                this.summary.enabled = 0;
                this.summary.disabled = 0;
                this.summary.backup = 0;
            }

            return this.servers.value;
        } catch (error) {
            console.error('Error loading servers:', error);
            let errorMsg = error.message || '网络连接错误';
            NotificationManager.show('error', 'Failed to load servers: ' + errorMsg);
            throw error;
        } finally {
            this.isLoading.value = false;
        }
    }

    getModalTitle() {
        if (!this.isEditing.value) return 'Create Server Configuration';
        if (this.isEditorReadOnly.value) return `View Server: ${this.editForm.value.name}`;
        return `Edit Server: ${this.editForm.value.name}`;
    }

    async handleServerCardClick(server) {
        try {
            this.isLoading.value = true;
            const response = await api.get(`/servers/${server.name}`);
            const serverData = response.data.data;
            this.isEditing.value = true;
            this.editForm.value = { name: serverData.name, content: serverData.content };
            this.editError.value = '';

            if (serverData.status === 'enabled') {
                this.isEditorReadOnly.value = true;
                this.showSaveButton.value = false;
                this.showTestButton.value = false;
                this.showEnableButton.value = false;
                this.showDisableButton.value = true;
            } else { // 'disabled' or 'backup'
                this.isEditorReadOnly.value = false;
                this.showSaveButton.value = true;
                this.showTestButton.value = false;
                this.showEnableButton.value = false;
                this.showDisableButton.value = false;
            }

            this.currentServer.value = serverData;
            this.showEditModal.value = true;
            
            // Initialize editor in the next tick after DOM is updated
            Vue.nextTick(this.initEditor);
        } catch (error) {
            console.error('Error loading server:', error);
            NotificationManager.show('error', 'Failed to load server: ' + (error.message || 'Unknown error'));
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 打开创建服务器模态框
     */
    openCreateModal() {
        this.isEditing.value = false;
        this.isEditorReadOnly.value = false;
        this.editForm.value = {
            name: '',
            content: 'server {\n    listen 80;\n    server_name example.com;\n    \n    location / {\n        return 200 "Hello World";\n    }\n}'
        };
        this.editError.value = '';
        this.showSaveButton.value = true;
        this.showTestButton.value = false;
        this.showEnableButton.value = false;
        this.showDisableButton.value = false;
        this.showEditModal.value = true;
        Vue.nextTick(this.initEditor);
    }

    /**
     * 打开编辑服务器模态框
     */
    async editServer(serverName) {
        this.showTestButtonInModal.value = false;
        try {
            this.isLoading.value = true;
            const response = await api.get(`/servers/${serverName}`);
            
            if (response && response.data && response.data.code === 200 && response.data.data) {
                this.isEditing.value = true;
                this.editForm.value = {
                    name: response.data.data.name || serverName,
                    content: response.data.data.content || ''
                };
                this.editError.value = '';
                this.showEditModal.value = true;
                Vue.nextTick(this.initEditor);
            } else if (response) {
                console.error('API error when loading server:', response);
                let errorMsg = response.message || '服务器返回错误';
                NotificationManager.show('error', 'Failed to load server: ' + errorMsg);
            } else {
                console.error('Empty API response when loading server');
                NotificationManager.show('error', 'Failed to load server: Empty response');
            }
        } catch (error) {
            console.error('Error loading server:', error);
            let errorMsg = error.message || '网络连接错误';
            NotificationManager.show('error', 'Failed to load server: ' + errorMsg);
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 从查看模态框切换到编辑模态框
     */
    editFromView() {
        if (this.currentServer.value) {
            this.closeViewModal();
            this.editServer(this.currentServer.value.name);
        }
    }

    /**
     * 关闭编辑模态框
     */
    closeEditModal() {
        if (this.editorInstance) {
            this.editorInstance.toTextArea();
            this.editorInstance = null;
        }
        this.showEditModal.value = false;
    }

    /**
     * 保存服务器配置
     */
    async saveServer() {
        if (!this.editForm.value.name.trim()) {
            this.editError.value = 'Server name is required';
            return;
        }

        if (!this.editForm.value.content.trim()) {
            this.editError.value = 'Server configuration is required';
            return;
        }

        try {
            this.isSaving.value = true;
            this.editError.value = ''; // Clear previous errors
            this.showTestButton.value = false; // Hide test button until success
            let response;
            
            if (this.isEditing.value) {
                // 更新现有服务器
                this.editForm.value.content = this.editorInstance.getValue(); // Get latest content
                response = await api.put(`/servers/${this.editForm.value.name}`, this.editForm.value.content, {
                    headers: {
                        'Content-Type': 'text/plain'
                    }
                });
            } else {
                // 创建新服务器
                this.editForm.value.content = this.editorInstance.getValue(); // Get latest content
                response = await api.post(`/servers/${this.editForm.value.name}`, this.editForm.value.content, {
                    headers: {
                        'Content-Type': 'text/plain'
                    }
                });
            }
            
            if (response && response.data && (response.data.code === 200 || response.data.code === 201)) {
                NotificationManager.show('success', response.data.message || 'Server saved successfully');
                this.refreshServerList();
                this.showTestButton.value = true;
                this.showEnableButton.value = false;
                if (!this.isEditing.value) {
                    this.isEditing.value = true;
                }
            } else if (response) {
                console.error('API error when saving server:', response);
                this.editError.value = response.data?.message || 'Failed to save server configuration';
            } else {
                console.error('Empty API response when saving server');
                this.editError.value = 'Failed to save server configuration: Empty response';
            }
        } catch (error) {
            console.error('Error saving server:', error);
            this.editError.value = error.message || 'Failed to save server configuration';
        } finally {
            this.isSaving.value = false;
        }
    }

    /**
     * 查看服务器配置
     */
    async viewServer(serverName) {
        try {
            this.isLoading.value = true;
            const response = await api.get(`/servers/${serverName}`);
            
            if (response && response.data && response.data.code === 200 && response.data.data) {
                this.currentServer.value = response.data.data;
                this.showViewModal.value = true;
                Vue.nextTick(this.initViewEditor);
            } else if (response) {
                console.error('API error when viewing server:', response);
                let errorMsg = response.message || '服务器返回错误';
                NotificationManager.show('error', 'Failed to load server: ' + errorMsg);
            } else {
                console.error('Empty API response when viewing server');
                NotificationManager.show('error', 'Failed to load server: Empty response');
            }
        } catch (error) {
            console.error('Error loading server:', error);
            let errorMsg = error.message || '网络连接错误';
            NotificationManager.show('error', 'Failed to load server: ' + errorMsg);
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 关闭查看模态框
     */
    closeViewModal() {
        if (this.viewEditorInstance) {
            this.viewEditorInstance = null; // Just nullify, no complex cleanup needed
        }
        this.showViewModal.value = false;
        this.currentServer.value = null;
    }

    /**
     * 确认删除服务器
     */
    confirmDeleteServer(serverName) {
        NotificationManager.confirm({
            title: '删除服务器',
            message: `确定要删除服务器配置 <b>${serverName}</b> 吗？<br>此操作无法撤销。`,
            confirmText: '删除',
            cancelText: '取消',
            dangerStyle: true,
            onConfirm: () => this.deleteServer(serverName)
        });
    }

    /**
     * 删除服务器
     */
    async deleteServer(serverNameToDelete) {
        const serverName = serverNameToDelete || this.deleteTarget.value;
        if (!serverName) return;
        
        try {
            this.isLoading.value = true;
            const response = await api.delete(`/servers/${serverName}`);
            
            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Server configuration deleted successfully');
                this.refreshServerList();
            } else if (response) {
                console.error('API error when deleting server:', response);
                let errorMsg = response.message || '服务器返回错误';
                NotificationManager.show('error', 'Failed to delete server: ' + errorMsg);
            } else {
                console.error('Empty API response when deleting server');
                NotificationManager.show('error', 'Failed to delete server: Empty response');
            }
        } catch (error) {
            console.error('Error deleting server:', error);
            let errorMsg = error.message || '网络连接错误';
            NotificationManager.show('error', 'Failed to delete server: ' + errorMsg);
        } finally {
            this.isLoading.value = false;
        }
    }

    /**
     * 测试服务器配置
     */
    async testServer() {
        const serverName = this.editForm.value.name;
        if (!serverName) return;

        try {
            this.isTesting.value = true;
            this.showTestButton.value = false; // Hide button on click
            // Mark server in the main list as processing
            const serverIndex = this.servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) {
                this.servers.value[serverIndex].isProcessing = true;
            }
            
            const response = await api.post(`/servers/${serverName}/action?action=test`);
            
            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Test passed');
                this.showTestButton.value = false;
                this.showEnableButton.value = true;
            } else if (response) {
                console.error('API error when testing server:', response);
                let errorMsg = response.data?.message || '服务器返回错误';
                NotificationManager.show('error', 'Server configuration test failed: ' + errorMsg);
            } else {
                console.error('Empty API response when testing server');
                NotificationManager.show('error', 'Server configuration test failed: Empty response');
            }
        } catch (error) {
            console.error('Error testing server:', error);
            let errorMsg = error.message || '网络连接错误';
            NotificationManager.show('error', 'Failed to test server: ' + errorMsg);
        } finally {
            this.isTesting.value = false;
            // Un-mark server in the main list
            const serverIndex = this.servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) {
                this.servers.value[serverIndex].isProcessing = false;
            }
        }
    }

    async enableServer(serverName) {
        if (!serverName) return;
        try {
            const serverIndex = this.servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) this.servers.value[serverIndex].isProcessing = true;
            
            const response = await api.post(`/servers/${serverName}/action?action=enable`);
            
            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Server enabled');
                await this.refreshServerList();
            } else {
                NotificationManager.show('error', 'Failed to enable server: ' + (response.data?.message || 'Unknown error'));
            }
        } catch (error) {
            NotificationManager.show('error', 'Failed to enable server: ' + (error.message || 'Unknown error'));
        } finally {
            const serverIndex = this.servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) this.servers.value[serverIndex].isProcessing = false;
        }
    }
    
    async disableServer(serverName) {
        if (!serverName) return;
        try {
            const serverIndex = this.servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) this.servers.value[serverIndex].isProcessing = true;

            const response = await api.post(`/servers/${serverName}/action?action=disable`);

            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Server disabled');
                await this.refreshServerList();
            } else {
                NotificationManager.show('error', 'Failed to disable server: ' + (response.data?.message || 'Unknown error'));
            }
        } catch (error) {
            NotificationManager.show('error', 'Failed to disable server: ' + (error.message || 'Unknown error'));
        } finally {
            const serverIndex = this.servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) this.servers.value[serverIndex].isProcessing = false;
        }
    }

    async enableServerFromModal() {
        const serverName = this.editForm.value.name;
        await this.enableServer(serverName);
        if (this.showEditModal.value) {
            this.closeEditModal();
        }
    }

    async disableServerFromModal() {
        const serverName = this.editForm.value.name;
        await this.disableServer(serverName);
        if (this.showEditModal.value) {
            this.closeEditModal();
        }
    }

    /**
     * 初始化 CodeMirror 编辑器
     */
    initEditor() {
        const textArea = document.getElementById('server-config-editor');
        if (textArea) {
            if (this.editorInstance) {
                this.editorInstance.toTextArea();
                this.editorInstance = null;
            }
            this.editorInstance = CodeMirror.fromTextArea(textArea, {
                mode: 'nginx',
                theme: 'dracula',
                lineNumbers: true,
                lineWrapping: true,
                readOnly: this.isEditorReadOnly.value
            });
            this.editorInstance.on('change', () => {
                this.editForm.value.content = this.editorInstance.getValue();
            });
        }
    }
    
    /**
     * 初始化只读的 CodeMirror 查看器
     */
    initViewEditor() {
        const viewDiv = document.getElementById('server-config-viewer');
        if (viewDiv) {
            // Clear previous instance if any
            viewDiv.innerHTML = '';
            this.viewEditorInstance = CodeMirror(viewDiv, {
                value: this.currentServer.value?.content || '',
                mode: 'nginx',
                theme: 'dracula',
                lineNumbers: true,
                readOnly: true,
                lineWrapping: true
            });
        }
    }

    /**
     * 获取服务器名称列表（从配置内容中提取）
     */
    getServerNames(server) {
        if (!server) {
            return 'N/A';
        }
        
        // 如果API已经提供了server_name，直接使用
        if (server.server_name) {
            return server.server_name;
        }
        
        // 尝试从内容中提取server_name指令
        if (server.content) {
            const match = server.content.match(/server_name\s+([^;]+);/);
            if (match && match[1]) {
                return match[1].trim();
            }
        }

        return 'N/A';
    }

    /**
     * 处理ESC键关闭模态框
     */
    handleEscKey() {
        if (this.showEditModal.value) {
            this.closeEditModal();
        } else if (this.showViewModal.value) {
            this.closeViewModal();
        } else if (this.showDeleteModal.value) {
            this.showDeleteModal.value = false;
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
        if (this.editorInstance) {
            this.editorInstance.toTextArea();
            this.editorInstance = null;
        }
        if (this.viewEditorInstance) {
            this.viewEditorInstance = null;
        }
        this.showEditModal.value = false;
        this.showViewModal.value = false;
        this.showDeleteModal.value = false;
        this.servers.value = [];
    }
}

// 创建全局ServersManager类
window.ServersManager = ServersManager; 