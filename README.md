# Patrol - 轻量级系统巡检工具

## 项目简介

Patrol 是一个基于 Shell 脚本实现的自动化系统巡检工具，用于运维场景。它通过 SSH 直连被控服务器执行检查命令，无需在被控机安装任何 Agent。

## 项目背景
在生产环境中，安全管控严格，无互联网连接，不能轻易安装软件。维护人员巡检应用服务器设备依靠人工操作，既费力又价值低。为此，开发一款轻量的巡检工具，针对 Linux 服务器，能够编辑安装部署，自动巡检，输出多格式巡检结果，并提供 Web 端巡检报告查看功能。

## 功能特性

- 支持多台服务器、多项检查命令的配置
- 输出三种格式报告：HTML（人类可读）、JSON（供下游系统）、TXT（纯文本日志）
- 提供趋势分析功能，展示系统资源使用情况的变化趋势
- 支持应用和 Docker 容器运行时长显示
- 跨系统兼容性，支持不同 Linux 发行版（如 Rocky Linux、Debian）
- 提供一键安装脚本，降低使用门槛
- 提供 --demo 模式，使用本地样本数据展示完整功能
- 纯 Shell 实现（bash 3.2+），尽量减少外部依赖
- 支持自定义配置文件，通过命令行参数指定

## 系统要求

### 中心机
- Bash 脚本环境
- 依赖工具：ssh、scp（系统自带）
- 内置 jq 工具（无需安装）

### 远程机
- Bash 脚本环境
- 依赖工具：vmstat、free、df、ps、awk（系统自带，不依赖 bc）
- 可选：docker（用于检查 Docker 相关信息）

### 兼容系统
- Redhat
- CentOs
- Rocky Linux
- Debian
- Ubuntu
- 其他Linux

## 目录结构

```
patrol/
├── patrol.sh          # 主调度脚本
├── remote_collector.sh # 远程数据采集脚本
├── install.sh         # 安装脚本
├── conf/              # 配置目录
│   ├── servers.conf             # 服务器配置
│   ├── servers.conf.example     # 服务器配置示例
│   ├── checks.conf              # 检查项配置
│   ├── checks.conf.example      # 检查项配置示例
│   ├── check_groups.conf        # 检查项分组配置
│   └── check_groups.conf.example # 检查项分组配置示例
├── logs/              # 日志目录
├── bin/               # 二进制工具目录（如 jq）
└── web/               # 前端页面目录
    ├── index.html              # 报告列表页面
    ├── report.html             # 概览报告页面
    ├── report_detailed.html    # 详细报告页面
    ├── trend.html              # 趋势分析页面
    ├── css/                    # 样式文件
    ├── js/                     # JavaScript 文件
    ├── data/                   # 报告数据目录
    └── demo_data/              # 演示数据目录
```

## 安装

1. 克隆项目到本地
2. 进入 patrol 目录：
   ```bash
   cd patrol
   ```
3. 运行一键安装脚本：
   ```bash
   chmod +x install.sh
   ./install.sh
   ```
4. 安装脚本会：
   - 检查必要命令（ssh、sshpass 可选、jq）
   - 若缺少 jq，自动下载对应平台的静态二进制
   - 创建所需目录结构，包括 `web` 目录及其子目录
   - 创建 SSH 密钥存储目录 `$HOME/patrol/.autopriv`
   - 复制配置文件示例
   - 提示如何生成 SSH 密钥对并推送公钥

## 配置

1. 复制配置文件示例并修改：
   ```bash
   cp conf/servers.conf.example conf/servers.conf
   cp conf/checks.conf.example conf/checks.conf
   cp conf/check_groups.conf.example conf/check_groups.conf
   ```

2. 编辑 `servers.conf` 配置服务器信息：
   ```
   # 格式：别名:IP:端口:用户名:私钥路径:密码（可选）:组标签`
   web01:192.168.1.10:22:root:$HOME/patrol/.autopriv/patrol_rsa:group_web
   db01:192.168.1.20:22:mysqluser:$HOME/patrol/.autopriv/patrol_rsa:mypassword:group_db
   ```

3. 编辑 `checks.conf` 配置检查项：
   ```
   # 格式：检查项名称:类型:执行命令
   # 系统基础信息
   system:system:cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"'
   kernel:system:uname -r
   # CPU 信息
   cpu:cpu:top -bn1 | grep 'Cpu(s)'
   # 内存信息
   mem:mem:free -m
   # 磁盘信息
   disk:disk:df -h
   # 进程检查
   nginx:vhost:ps aux | grep -E "(nginx|nginx:)" | grep -v grep
   # Docker 检查
   oracle_19c:docker:docker ps --filter "name=oracle"
   ```

4. 编辑 `check_groups.conf` 配置检查项分组：
   ```
   # 格式：分组名:检查项1,检查项2,...
   # 192.168.1.1 主机检查项分组
   group_1_1:nginx,system,kernel,uptime
   # 192.168.1.2 主机检查项分组
   group_1_2:mysql,redis,memcached,system,kernel,uptime
   # 通用检查项分组
   group_system:system,kernel,architecture,uptime
   group_resource:cpu,mem,disk,disk_root,disk_home
   group_apps:nginx,mysql,redis,memcached
   group_docker:kafka,oracle_19c,opengauss,cordys-crm
   ```

## 使用

### 运行模式

```bash
# 默认配置文件模式
./patrol.sh

# 自定义巡检配置模式（支持 conf/ 前缀省略）
./patrol.sh --servers=servers_local.conf --groups=check_groups_solo.conf --checks=checks_solo.conf

# 或者使用完整路径
./patrol.sh --servers=conf/servers_local.conf --groups=conf/check_groups_solo.conf --checks=conf/checks_solo.conf

# Demo 模式（使用预设数据快速生成报告）
./patrol.sh --demo
```

### 并发执行

```bash
./patrol.sh --parallel 5
```

### 自定义配置文件

```bash
# 使用自定义服务器配置文件（支持省略 conf/ 前缀）
./patrol.sh --servers=servers_test.conf

# 使用自定义分组配置文件
./patrol.sh --groups=check_groups_test.conf

# 使用自定义检查项配置文件
./patrol.sh --checks=checks_test.conf

# 同时使用多个自定义配置文件
./patrol.sh --servers=servers_test.conf --groups=check_groups_test.conf --checks=checks_test.conf
```

### 运行 Web 服务

```bash
# 方式一：使用 Python 内置 HTTP 服务器
cd web && python -m http.server 8000

# 方式二：使用 Nginx 配置
# 在 Nginx 配置文件中添加：
# server {
#     listen 8000;
#     server_name localhost;
#     root /path/to/patrol/web;
#     index index.html;
#     location / {
#         try_files $uri $uri/ =404;
#     }
# }

# 然后在浏览器中访问
# http://localhost:8000/index.html
```

## 报告输出

执行完成后，会在 `web/data/` 目录生成以下文件：
- `report_YYYYMMDD_HHMMSS.html` - HTML 格式概览报告（人类可读）
- `report_YYYYMMDD_HHMMSS.json` - JSON 格式报告（供下游系统）
- `report_YYYYMMDD_HHMMSS.txt` - TXT 格式报告（纯文本日志）
- `reports.json` - 所有巡检报告的摘要信息（用于趋势分析）

## 趋势分析

打开 `web/trend.html` 页面，可以查看系统资源使用情况的趋势图表，包括：
- CPU 使用率趋势
- 内存使用率趋势
- 磁盘使用率趋势
- 告警数量趋势

## 注意事项

1. 建议使用 SSH 密钥认证，避免在配置文件中存储密码
2. 若使用密码认证，需要安装 `sshpass` 工具
3. 确保执行脚本的用户有足够的权限
4. 定期清理 `web/data/` 目录，避免占用过多磁盘空间
5. 确保远程服务器上安装了必要的命令（如 top、free、df、ps、docker 等）


## 问题处理

- **无法连接到远程服务器**：检查网络连接、SSH 配置和服务器状态
- **远程脚本执行失败**：检查远程服务器的工具是否安装完整
- **报告生成失败**：检查 jq 工具是否正常工作
- **阈值告警不准确**：调整 checks.conf 中的阈值设置


## 故障排查

- 检查 `logs/` 目录下的日志文件
- 验证配置文件格式是否正确（使用冒号分隔）
- 检查远程服务器上的命令是否存在
- 查看远程服务器的系统日志以了解可能的问题

## 扩展功能

- **添加新检查项**：在 checks.conf 中添加新的检查项定义
- **创建新检查组**：在 check_groups.conf 中创建新的检查组
- **添加新服务器**：在 servers.conf 中添加新的服务器信息
- **自定义报告模板**：修改 HTML 报告模板以满足特定需求
