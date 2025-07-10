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

const ServersManager = (function() {
    // 使用Vue的响应式API
    const isLoading = Vue.ref(false);
    const isSaving = Vue.ref(false);
    const isTesting = Vue.ref(false);
    const showTestButtonInModal = Vue.ref(false);
    const lastUpdateTime = Vue.ref(null);
    const servers = Vue.ref([]);
    // 使用普通对象而不是ref对象，以便在HTML中直接访问
    const summary = {
        total: 0,
        enabled: 0,
        disabled: 0,
        backup: 0
    };

    // 模态框状态
    const showEditModal = Vue.ref(false);
    const showViewModal = Vue.ref(false);
    const showDeleteModal = Vue.ref(false);
    const isEditing = Vue.ref(false);
    const editError = Vue.ref('');
    const deleteTarget = Vue.ref('');
    const currentServer = Vue.ref(null);
    let editorInstance = null;
    let viewEditorInstance = null;
    
    // 编辑表单
    const editForm = Vue.ref({
        name: '',
        content: ''
    });

    // New state for unified modal
    const showSaveButton = Vue.ref(true);
    const showTestButton = Vue.ref(false);
    const showEnableButton = Vue.ref(false);
    const showDisableButton = Vue.ref(false);
    const isEditorReadOnly = Vue.ref(false);
    
    /**
     * 初始化模块
     */
    function init() {
        refreshServerList();
    }

    /**
     * 刷新服务器列表
     */
    async function refreshServerList() {
        try {
            isLoading.value = true;
            const response = await api.get('/servers');
            
            // 处理服务器列表数据
            if (response.data.data) {
                // 处理服务器列表
                if (response.data.data.items && Array.isArray(response.data.data.items)) {
                    // 确保每个服务器对象都有必要的属性
                    servers.value = response.data.data.items.map(server => ({
                        ...server,
                        isProcessing: false, // 添加处理状态属性
                        updated_at: server.updated_at ? new Date(server.updated_at * 1000) : new Date() // 转换时间戳为日期对象
                    }));
                } else {
                    console.warn('Server items missing or not an array in API response');
                    servers.value = [];
                }
                
                // 更新状态摘要
                if (response.data.data.status_summary) {
                    summary.total = response.data.data.status_summary.total || 0;
                    summary.enabled = response.data.data.status_summary.enabled || 0;
                    summary.disabled = response.data.data.status_summary.disabled || 0;
                    summary.backup = response.data.data.status_summary.backup || 0;
                } else {
                    // 手动计算状态摘要
                    let enabled = 0, disabled = 0, backup = 0;
                    servers.value.forEach(server => {
                        if (server.status === 'enabled') enabled++;
                        else if (server.status === 'disabled') disabled++;
                        else if (server.status === 'backup') backup++;
                    });
                    
                    summary.total = servers.value.length;
                    summary.enabled = enabled;
                    summary.disabled = disabled;
                    summary.backup = backup;
                }
                
                lastUpdateTime.value = new Date();
            } else {
                console.warn('Data missing in API response');
                servers.value = [];
                summary.total = 0;
                summary.enabled = 0;
                summary.disabled = 0;
                summary.backup = 0;
            }
        } catch (error) {
            console.error('Error loading servers:', error);
            let errorMsg = error.message || '网络连接错误';
            NotificationManager.show('error', 'Failed to load servers: ' + errorMsg);
        } finally {
            isLoading.value = false;
        }
    }

    // 移除了自动刷新相关的函数

    function getModalTitle() {
        if (!isEditing.value) return 'Create Server Configuration';
        if (isEditorReadOnly.value) return `View Server: ${editForm.value.name}`;
        return `Edit Server: ${editForm.value.name}`;
    }

    async function handleServerCardClick(server) {
        try {
            isLoading.value = true;
            const response = await api.get(`/servers/${server.name}`);
            const serverData = response.data.data;
            isEditing.value = true;
            editForm.value = { name: serverData.name, content: serverData.content };
            editError.value = '';

        if (serverData.status === 'enabled') {
            isEditorReadOnly.value = true;
            showSaveButton.value = false;
            showTestButton.value = false;
            showEnableButton.value = false;
            showDisableButton.value = true;
        } else { // 'disabled' or 'backup'
            isEditorReadOnly.value = false;
            showSaveButton.value = true;
            showTestButton.value = false;
            showEnableButton.value = false;
            showDisableButton.value = false;
        }
            
            currentServer.value = serverData;
            showEditModal.value = true;
            
            // Initialize editor in the next tick after DOM is updated
            Vue.nextTick(initEditor);
        } catch (error) {
            console.error('Error loading server:', error);
            NotificationManager.show('error', 'Failed to load server: ' + (error.message || 'Unknown error'));
        } finally {
            isLoading.value = false;
        }
    }

    /**
     * 打开创建服务器模态框
     */
    function openCreateModal() {
        isEditing.value = false;
        isEditorReadOnly.value = false;
        editForm.value = {
            name: '',
            content: 'server {\n    listen 80;\n    server_name example.com;\n    \n    location / {\n        return 200 "Hello World";\n    }\n}'
        };
        editError.value = '';
        showSaveButton.value = true;
        showTestButton.value = false;
        showEnableButton.value = false;
        showDisableButton.value = false;
        showEditModal.value = true;
        Vue.nextTick(initEditor);
    }

    /**
     * 打开编辑服务器模态框
     */
    async function editServer(serverName) {
        showTestButtonInModal.value = false;
        try {
            isLoading.value = true;
            const response = await api.get(`/servers/${serverName}`);
            
            if (response && response.data && response.data.code === 200 && response.data.data) {
                isEditing.value = true;
                editForm.value = {
                    name: response.data.data.name || serverName,
                    content: response.data.data.content || ''
                };
                editError.value = '';
                showEditModal.value = true;
                Vue.nextTick(initEditor);
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
            isLoading.value = false;
        }
    }

    /**
     * 从查看模态框切换到编辑模态框
     */
    function editFromView() {
        if (currentServer.value) {
            closeViewModal();
            editServer(currentServer.value.name);
        }
    }

    /**
     * 关闭编辑模态框
     */
    function closeEditModal() {
        if (editorInstance) {
            editorInstance.toTextArea();
            editorInstance = null;
        }
        showEditModal.value = false;
    }

    /**
     * 保存服务器配置
     */
    async function saveServer() {
        if (!editForm.value.name.trim()) {
            editError.value = 'Server name is required';
            return;
        }

        if (!editForm.value.content.trim()) {
            editError.value = 'Server configuration is required';
            return;
        }

        try {
            isSaving.value = true;
            editError.value = ''; // Clear previous errors
            showTestButton.value = false; // Hide test button until success
            let response;
            
            if (isEditing.value) {
                // 更新现有服务器
                editForm.value.content = editorInstance.getValue(); // Get latest content
                response = await api.put(`/servers/${editForm.value.name}`, editForm.value.content, {
                    headers: {
                        'Content-Type': 'text/plain'
                    }
                });
            } else {
                // 创建新服务器
                editForm.value.content = editorInstance.getValue(); // Get latest content
                response = await api.post(`/servers/${editForm.value.name}`, editForm.value.content, {
                    headers: {
                        'Content-Type': 'text/plain'
                    }
                });
            }
            
            if (response && response.data && (response.data.code === 200 || response.data.code === 201)) {
                NotificationManager.show('success', response.data.message || 'Server saved successfully');
                refreshServerList();
                showTestButton.value = true;
                showEnableButton.value = false;
                if (!isEditing.value) {
                    isEditing.value = true;
                }
            } else if (response) {
                console.error('API error when saving server:', response);
                editError.value = response.data?.message || 'Failed to save server configuration';
            } else {
                console.error('Empty API response when saving server');
                editError.value = 'Failed to save server configuration: Empty response';
            }
        } catch (error) {
            console.error('Error saving server:', error);
            editError.value = error.message || 'Failed to save server configuration';
        } finally {
            isSaving.value = false;
        }
    }

    /**
     * 查看服务器配置
     */
    async function viewServer(serverName) {
        try {
            isLoading.value = true;
            const response = await api.get(`/servers/${serverName}`);
            
            if (response && response.data && response.data.code === 200 && response.data.data) {
                currentServer.value = response.data.data;
                showViewModal.value = true;
                Vue.nextTick(initViewEditor);
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
            isLoading.value = false;
        }
    }

    /**
     * 关闭查看模态框
     */
    function closeViewModal() {
        if (viewEditorInstance) {
            viewEditorInstance = null; // Just nullify, no complex cleanup needed
        }
        showViewModal.value = false;
        currentServer.value = null;
    }

    /**
     * 确认删除服务器
     */
    function confirmDeleteServer(serverName) {
        NotificationManager.confirm({
            title: '删除服务器',
            message: `确定要删除服务器配置 <b>${serverName}</b> 吗？<br>此操作无法撤销。`,
            confirmText: '删除',
            cancelText: '取消',
            dangerStyle: true,
            onConfirm: () => deleteServer(serverName)
        });
    }

    /**
     * 删除服务器
     */
    async function deleteServer(serverNameToDelete) {
        const serverName = serverNameToDelete || deleteTarget.value;
        if (!serverName) return;
        
        try {
            isLoading.value = true;
            const response = await api.delete(`/servers/${serverName}`);
            
            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Server configuration deleted successfully');
                refreshServerList();
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
            isLoading.value = false;
        }
    }

    /**
     * 测试服务器配置
     */
    async function testServer() {
        const serverName = editForm.value.name;
        if (!serverName) return;

        try {
            isTesting.value = true;
            showTestButton.value = false; // Hide button on click
            // Mark server in the main list as processing
            const serverIndex = servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) {
                servers.value[serverIndex].isProcessing = true;
            }
            
            const response = await api.post(`/servers/${serverName}/action?action=test`);
            
            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Test passed');
                showTestButton.value = false;
                showEnableButton.value = true;
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
            isTesting.value = false;
            // Un-mark server in the main list
            const serverIndex = servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) {
                servers.value[serverIndex].isProcessing = false;
            }
        }
    }

    async function enableServer(serverName) {
        if (!serverName) return;
        try {
            const serverIndex = servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) servers.value[serverIndex].isProcessing = true;
            
            const response = await api.post(`/servers/${serverName}/action?action=enable`);
            
            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Server enabled');
                await refreshServerList();
            } else {
                NotificationManager.show('error', 'Failed to enable server: ' + (response.data?.message || 'Unknown error'));
            }
        } catch (error) {
            NotificationManager.show('error', 'Failed to enable server: ' + (error.message || 'Unknown error'));
        } finally {
            const serverIndex = servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) servers.value[serverIndex].isProcessing = false;
        }
    }
    
    async function disableServer(serverName) {
        if (!serverName) return;
        try {
            const serverIndex = servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) servers.value[serverIndex].isProcessing = true;

            const response = await api.post(`/servers/${serverName}/action?action=disable`);

            if (response && response.data && response.data.code === 200) {
                NotificationManager.show('success', response.data.message || 'Server disabled');
                await refreshServerList();
            } else {
                NotificationManager.show('error', 'Failed to disable server: ' + (response.data?.message || 'Unknown error'));
            }
        } catch (error) {
            NotificationManager.show('error', 'Failed to disable server: ' + (error.message || 'Unknown error'));
        } finally {
            const serverIndex = servers.value.findIndex(s => s.name === serverName);
            if (serverIndex >= 0) servers.value[serverIndex].isProcessing = false;
        }
    }

    async function enableServerFromModal() {
        const serverName = editForm.value.name;
        await enableServer(serverName);
        if (showEditModal.value) {
            closeEditModal();
        }
    }

    async function disableServerFromModal() {
        const serverName = editForm.value.name;
        await disableServer(serverName);
        if (showEditModal.value) {
            closeEditModal();
        }
    }

    /**
     * 初始化 CodeMirror 编辑器
     */
    function initEditor() {
        const textArea = document.getElementById('server-config-editor');
        if (textArea) {
            if(editorInstance) {
                editorInstance.toTextArea();
                editorInstance = null;
            }
            editorInstance = CodeMirror.fromTextArea(textArea, {
                mode: 'nginx',
                theme: 'dracula',
                lineNumbers: true,
                lineWrapping: true,
                readOnly: isEditorReadOnly.value
            });
            editorInstance.on('change', () => {
                editForm.value.content = editorInstance.getValue();
            });
        }
    }
    
    /**
     * 初始化只读的 CodeMirror 查看器
     */
    function initViewEditor() {
        const viewDiv = document.getElementById('server-config-viewer');
        if (viewDiv) {
            // Clear previous instance if any
            viewDiv.innerHTML = '';
            viewEditorInstance = CodeMirror(viewDiv, {
                value: currentServer.value?.content || '',
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
    function getServerNames(server) {
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

    // 返回公共API
    return {
        // 状态
        isLoading,
        isSaving,
        isTesting,
        showTestButtonInModal,
        lastUpdateTime,
        servers,
        summary,
        showEditModal,
        showViewModal,
        isEditing,
        editError,
        deleteTarget,
        currentServer,
        editForm,
        showSaveButton,
        showTestButton,
        showEnableButton,
        showDisableButton,
        isEditorReadOnly,

        // 方法
        init,
        refreshServerList,
        openCreateModal,
        editServer,
        editFromView,
        closeEditModal,
        saveServer,
        viewServer,
        closeViewModal,
        confirmDeleteServer,
        deleteServer,
        testServer,
        enableServer,
        disableServer,
        getServerNames,
        handleServerCardClick,
        getModalTitle,
        enableServerFromModal,
        disableServerFromModal
    };
})();

// 初始化
document.addEventListener('DOMContentLoaded', function() {
    // ServersManager.init() 将在main.js中调用
}); 