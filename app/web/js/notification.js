const NotificationManager = (() => {
    const notifications = Vue.ref([]);
    let notificationId = 0;

    // 确认对话框状态
    const confirmDialog = Vue.reactive({
        show: false,
        title: '确认操作',
        message: '确定要执行此操作吗？',
        confirmText: '确认',
        cancelText: '取消',
        dangerStyle: true,
        onConfirm: null,
        onCancel: null,
        confirm() {
            confirmDialog.show = false;
            if (typeof confirmDialog.onConfirm === 'function') {
                confirmDialog.onConfirm();
            }
        },
        cancel() {
            confirmDialog.show = false;
            if (typeof confirmDialog.onCancel === 'function') {
                confirmDialog.onCancel();
            }
        }
    });

    /**
     * 显示通知
     * @param {string} message 消息内容
     * @param {string} type 通知类型：success, error, warning, info
     * @param {number} duration 显示时长（毫秒）
     */
    function show(type = 'info',message,  duration = 3000) {
        const id = ++notificationId;
        const icons = {
            success: '✅',
            error: '❌',
            warning: '⚠️',
            info: 'ℹ️'
        };
        notifications.value.push({
            id,
            type,
            message,
            icon: icons[type] || icons.info,
            leaving: false
        });
        setTimeout(() => {
            const idx = notifications.value.findIndex(n => n.id === id);
            if (idx !== -1) {
                notifications.value[idx].leaving = true;
                setTimeout(() => {
                    notifications.value = notifications.value.filter(n => n.id !== id);
                }, 400);
            }
        }, duration);
    }

    /**
     * 清除所有通知
     */
    function clear() {
        notifications.value = [];
    }

    /**
     * 显示确认对话框
     * @param {Object} options 配置选项
     * @param {string} options.title 标题
     * @param {string} options.message 消息内容（支持HTML）
     * @param {string} options.confirmText 确认按钮文本
     * @param {string} options.cancelText 取消按钮文本
     * @param {boolean} options.dangerStyle 是否使用危险样式（红色确认按钮）
     * @param {Function} options.onConfirm 确认回调
     * @param {Function} options.onCancel 取消回调
     */
    function confirm(options) {
        confirmDialog.title = options.title || '确认操作';
        confirmDialog.message = options.message || '确定要执行此操作吗？';
        confirmDialog.confirmText = options.confirmText || '确认';
        confirmDialog.cancelText = options.cancelText || '取消';
        confirmDialog.dangerStyle = options.dangerStyle !== false;
        confirmDialog.onConfirm = options.onConfirm || null;
        confirmDialog.onCancel = options.onCancel || null;
        confirmDialog.show = true;
    }

    return {
        notifications,
        confirmDialog,
        show,
        clear,
        confirm
    };
})();

window.NotificationManager = NotificationManager; 