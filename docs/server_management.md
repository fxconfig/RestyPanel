# Server 管理系统

## 概述

RestyPanel 的 Server 管理系统提供了智能化的 nginx server 块配置管理功能，支持配置文件的自动状态管理和安全测试机制。

## 文件管理策略

### 文件命名规则

- **启用状态**: `server_<name>.conf` - 正常生效的配置
- **禁用状态**: `server_<name>.conf.disabled` - 手动禁用的配置  
- **失败状态**: `server_<name>.conf.failed` - 测试失败的配置
- **备份文件**: `server_<name>.conf.backup` - 待测试的配置

### nginx.conf 集成

```nginx
# 在 nginx.conf 的 http 块中添加
include /app/configs/server_*.conf;
```

只有 `server_*.conf` 格式的文件会被 nginx 加载，其他状态的文件不会影响 nginx 运行。

## API 端点

### 基础 CRUD 操作

| 方法 | 端点 | 描述 |
|------|------|------|
| GET | `/servers` | 获取所有 server 配置列表 |
| GET | `/servers/{name}` | 获取指定 server 配置内容 |
| POST | `/servers/{name}` | 创建新的 server 配置（保存为 backup 状态） |
| PUT | `/servers/{name}` | 更新 server 配置（保存为 backup 状态） |
| DELETE | `/servers/{name}` | 删除 server 配置 |

### 状态管理操作

| 方法 | 端点 | 描述 |
|------|------|------|
| POST | `/servers/{name}/action?action=test` | 测试配置（backup → disabled） |
| POST | `/servers/{name}/action?action=enable` | 启用配置（disabled → enabled） |
| POST | `/servers/{name}/action?action=disable` | 禁用配置（enabled → disabled） |

### 状态流转机制

#### 状态流转图

```
                         ┌───── update ─────┐
                         ↓                  │
创建新配置 ─────→ backup (待测试) ───┐       │
                                    │       │
                               test │       │
                                    ↓       │
                       ┌────── disabled ◄───┘
                       │       (已禁用)
                       │           ↑
               enable  │           │  disable
                       │           │
                       └───────→ enabled
                                (生效中)
```

#### 状态流转规则

1. **创建操作**：所有新配置都保存为 `backup` 状态
   - 新创建的服务器配置保存为备份状态，等待测试

2. **测试操作**：只能对 `backup` 状态的文件进行测试
   - 测试成功: `backup` → `disabled`
   - 测试失败: 保持 `backup` 状态，不会改变状态

3. **启用操作**：只能对 `disabled` 状态的文件进行启用
   - 启用成功: `disabled` → `enabled` (生效并自动重载nginx)
   - 启用失败: 回滚到 `disabled` 状态

4. **禁用操作**：只能对 `enabled` 状态的文件进行禁用
   - 禁用成功: `enabled` → `disabled` (停止生效并自动重载nginx)
   - 禁用失败: 回滚到 `enabled` 状态

5. **更新操作**：只能对 `disabled` 状态的文件进行更新
   - 更新操作会将配置保存为 `backup` 状态，等待测试

#### 状态文件说明

| 状态 | 文件后缀 | 描述 | 可执行操作 |
|------|---------|------|----------|
| enabled | `.conf` | 正常生效的配置 | disable |
| disabled | `.conf.disabled` | 已禁用的配置 | enable, update |
| backup | `.conf.backup` | 待测试的新配置 | test |

#### 状态文件管理

为确保每个服务器只存在一个状态文件，系统实现以下规则：

1. 每次执行操作时，会先删除所有状态的文件，然后创建目标状态的文件
2. `.conf`文件会被nginx自动加载，其他后缀的文件不会被加载
3. 所有操作前都会检查当前服务器状态，只允许在合适的状态下执行操作

#### 操作流程示例

**添加新服务器流程**：
1. POST新服务器 → 生成`backup`状态文件
2. 前端执行test动作 → 测试通过 → 变为`disabled`状态
3. 前端执行enable动作 → 变为`enabled`状态 → 服务器生效

**修改现有服务器流程**：
1. 先将服务器禁用(disable) → 变为`disabled`状态
2. 执行update修改 → 变为`backup`状态
3. 前端执行test动作 → 测试通过 → 变为`disabled`状态
4. 前端执行enable动作 → 变为`enabled`状态 → 服务器生效

## 配置状态说明

### backup (待测试)
- 文件名: `server_<name>.conf.backup`
- 描述: 新创建或更新的配置，等待测试
- 可用操作: `test`
- 颜色标识: 黄色

### disabled (已禁用)  
- 文件名: `server_<name>.conf.disabled`
- 描述: 配置已通过测试但被禁用，不参与 nginx 加载
- 可用操作: `enable`
- 颜色标识: 灰色

### enabled (生效中)
- 文件名: `server_<name>.conf`
- 描述: 配置已通过测试并正在生效
- 可用操作: `disable`
- 颜色标识: 绿色

### failed (测试失败)
- 文件名: `server_<name>.conf.failed`  
- 描述: 配置未通过 nginx 测试，未生效
- 可用操作: `test`
- 颜色标识: 红色

## 安全机制

### 1. 状态隔离
- 每个操作只能针对特定状态的文件
- 防止误操作和状态混乱
- 严格的状态流转控制

### 2. 自动测试
- 所有配置变更都会自动执行 `nginx -t` 测试
- 测试失败时自动回滚到原状态
- 测试成功后自动执行 `nginx -s reload`

### 3. 备份恢复
- 更新配置前自动备份原配置
- 测试失败时自动恢复备份配置
- 删除操作前备份，失败时可恢复

## 使用示例

### 创建 server 配置

```http
POST /api/servers/example
Content-Type: text/plain

server {
    listen 80;
    server_name example.com;
    
    location / {
        proxy_pass http://backend_upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 测试配置

```http
POST /api/servers/example/action?action=test
Authorization: Bearer {{access_token}}
```

### 启用配置

```http
POST /api/servers/example/action?action=enable
Authorization: Bearer {{access_token}}
```

### 禁用配置

```http
POST /api/servers/example/action?action=disable
Authorization: Bearer {{access_token}}
```

### 更新配置

```http
PUT /api/servers/example
Content-Type: text/plain

server {
    listen 80;
    server_name example.com www.example.com;
    
    location / {
        proxy_pass http://backend_upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 响应格式

创建配置的响应：

```json
{
    "code": 201,
    "message": "Server config created in backup state. Use action=test to validate.",
    "data": {
        "name": "example",
        "status": "backup",
        "enabled": false,
        "description": "待测试状态",
        "size": 234,
        "created_at": 1704067200,
        "updated_at": 1704067200,
        "next_actions": ["test"]
    },
    "detail": {
        "message": "Configuration saved as backup. Use POST /servers/example/action?action=test to validate and move to disabled state."
    }
}
```

测试成功的响应：

```json
{
    "code": 200,
    "message": "Server configuration test passed",
    "data": {
        "name": "example",
        "action": "test",
        "status": "success",
        "previous_state": "backup",
        "current_state": "disabled",
        "message": "Configuration test passed, moved to disabled state"
    },
    "detail": {
        "test_output": "nginx: configuration file test is successful"
    }
}
```

### 错误处理

测试失败时的响应：

```json
{
    "code": 500,
    "message": "Server configuration test failed",
    "data": {
        "name": "example",
        "action": "test",
        "status": "failed",
        "current_state": "backup",
        "message": "Configuration test failed, backup file unchanged"
    },
    "detail": {
        "test_output": "nginx: [emerg] unknown directive \"invalid_directive\""
    }
}
```

## 前端集成

### 状态显示
- 使用不同颜色和图标显示配置状态
- 显示每个状态可用的操作按钮
- 显示详细的状态描述和流转提示

### 操作反馈
- 实时显示操作结果和状态变化
- 错误时显示具体错误信息和回滚状态
- 成功时显示测试和重载结果

### 文件管理
- 支持在线编辑配置内容
- 提供语法高亮和验证
- 实时预览配置效果
- 显示状态流转路径

## 最佳实践

1. **配置命名**: 使用有意义的名称，如 `api_server`、`static_server`
2. **状态管理**: 严格按照状态流转规则操作，避免跳过测试步骤
3. **测试策略**: 在生产环境中先测试配置，确认无误后再启用
4. **备份管理**: 重要配置变更前手动备份
5. **监控告警**: 配置测试失败时及时处理
6. **版本控制**: 将配置文件纳入版本控制系统 