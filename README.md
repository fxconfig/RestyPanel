# RestyPanel

基于 OpenResty 的轻量级网关管理面板，提供可视化配置、API 管理和流量控制功能。

## 项目介绍

RestyPanel 是一个功能强大的 Web 管理界面，用于配置和监控基于 OpenResty/Nginx 的网关服务。它提供了直观的 UI 界面，使管理员可以轻松管理 Nginx 配置、监控流量、控制访问权限，并提供多种高级功能。

### 核心特性

- **服务器配置管理**：可视化创建、编辑、测试和部署 Nginx 服务器配置
- **智能状态管理**：配置文件状态流转机制，确保安全测试与部署
- **流量控制**：频率限制、IP 过滤、URI 重写等功能
- **安全增强**：浏览器验证、协议锁定、重定向控制
- **上游服务管理**：简化后端服务的配置和负载均衡
- **实时监控**：流量统计和状态监控
- **API 系统**：内置 RESTful API 用于自动化管理

## 快速开始

### 使用 Docker 部署

1. 克隆仓库

```bash
git clone https://github.com/fxconfig/RestyPanel.git
cd RestyPanel
```

2. 启动容器

```bash
docker-compose up -d
```

3. 访问管理界面

打开浏览器访问：`http://localhost:8765`

## 系统架构

RestyPanel 基于 OpenResty 构建，通过 Lua 脚本扩展 Nginx 的功能：

- **前端**：基于 Vue.js 的单页应用
- **后端**：OpenResty (Nginx + Lua) 提供 API 和核心功能
- **配置**：基于文件的配置管理系统，自动处理配置状态

## 配置管理

RestyPanel 使用严格的配置状态管理系统：

1. **创建/更新配置**：配置保存为 `backup` 状态
2. **测试配置**：通过测试后变为 `disabled` 状态
3. **启用配置**：将配置从 `disabled` 变为 `enabled` 状态，自动重载 Nginx
4. **禁用配置**：将配置从 `enabled` 变为 `disabled` 状态

详细信息请查看 [服务器管理文档](docs/server_management.md)

## 开发指南

### 目录结构

```
RestyPanel/
  ├── app/                  # 应用程序代码
  │   ├── configs/          # 配置文件目录
  │   ├── lua/              # Lua 脚本
  │   │   ├── controllers/  # API 控制器
  │   │   ├── core/         # 核心功能
  │   │   ├── services/     # 业务服务
  │   │   └── resty/        # OpenResty 库
  │   └── web/              # 前端文件
  ├── logs/                 # 日志文件
  ├── scripts/              # 辅助脚本
  ├── docs/                 # 文档
  ├── Dockerfile            # Docker 构建文件
  └── nginx.conf            # Nginx 主配置文件
```

### API 文档

RestyPanel 提供完整的 RESTful API：

- 服务器配置管理 API
- 上游配置管理 API
- 安全功能 API
- 状态监控 API

## 贡献指南

欢迎提交 Pull Request 或创建 Issue 来帮助改进 RestyPanel！

## 许可证

本项目采用 [MIT 许可证](LICENSE)。

## 相关项目

- [OpenResty](https://openresty.org/)
- [Nginx](https://nginx.org/) 