var nodes_status = {
    init: function() {
        this.update_interval = 3; // 默认3秒更新一次
        this.start_update();
    },

    start_update: function() {
        var self = this;
        this.update();
        setInterval(function() {
            self.update();
        }, this.update_interval * 1000);
    },

    update: function() {
        var self = this;
        $.ajax({
            url: '/verynginx/nodes/status',
            type: 'GET',
            success: function(data) {
                self.update_table(data);
            },
            error: function(xhr, status, error) {
                console.error('Failed to get nodes status:', error);
            }
        });
    },

    update_table: function(data) {
        var tbody = $('#nodes_status_body');
        tbody.empty();

        for (var upstream in data) {
            for (var node in data[upstream]) {
                var nodeInfo = data[upstream][node];
                var row = $('<tr>');
                
                // 节点名称 (upstream:node)
                var nodeName = upstream + ':' + node;
                row.append($('<td>').text(nodeName));
                
                // 状态
                var status_cell = $('<td>');
                if (nodeInfo.is_healthy) {
                    status_cell.append($('<span class="label label-success">').text('正常'));
                } else {
                    status_cell.append($('<span class="label label-danger">').text('异常'));
                }
                row.append(status_cell);
                
                // 最后检查时间
                var last_check = nodeInfo.last_check ? new Date(nodeInfo.last_check * 1000) : new Date();
                row.append($('<td>').text(last_check.toLocaleString()));
                
                // 错误信息或状态
                var status_info = nodeInfo.last_error || (nodeInfo.is_healthy ? '正常' : '未知错误');
                row.append($('<td>').text(status_info));
                
                tbody.append(row);
            }
        }
    },

    set_update_interval: function(interval) {
        this.update_interval = interval;
        this.start_update();
    }
}; 