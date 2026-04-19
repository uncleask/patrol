# Patrol 系统巡检工具

## 项目背景
在生产环境中，安全管控严格，无互联网连接，不能轻易安装软件。维护人员巡检应用服务器设备依靠人工操作，既费力又价值低。为此，开发一款轻量的巡检工具，针对 Linux 服务器，能够编辑安装部署，自动巡检，输出多格式巡检结果，并提供 Web 端巡检报告查看功能。

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

## 安装方法

1. **离线部署**：
   - 将整个 patrol 目录复制到中心机
   - 运行安装脚本：
     ```bash
     chmod +x install.sh
     ./install.sh
     ```

2. **配置服务器**：
   - 编辑 `conf/servers.conf` 文件，添加服务器信息
   - 格式：`别名:IP:端口:用户:密钥:密码:组标签`

3. **设置免密登录**：
   - 安装脚本会自动生成 SSH 密钥对
   - 将生成的公钥添加到各服务器的 `~/.ssh/authorized_keys` 文件

## 目录结构

```
patrol/
├── patrol.sh              # 主调度脚本
├── remote_collector.sh    # 远程采集脚本
├── install.sh             # 安装脚本
├── bin/                   # 二进制工具（内置 jq）
├── conf/                  # 配置文件
│   ├── servers.conf
│   ├── check_groups.conf
│   └── checks.conf
├── output/                # 报告输出
├── logs/                  # 日志
└── web/                   # Web 展示
    ├── index.html
    ├── css/
    └── js/
```

## 配置文件说明

### 1. servers.conf（服务器配置）
格式：`别名:IP:端口:用户:密钥:密码:组标签`

示例：
```
# 本地环境服务器
local-server:127.0.0.1:22:root:./patrol/.ssh/id_rsa:password:local web

# 生产环境服务器
prod-web1:192.168.1.100:22:root:./patrol/.ssh/id_rsa:password123:prod web
prod-web2:192.168.1.101:22:root:./patrol/.ssh/id_rsa:password123:prod web
prod-db1:192.168.1.110:22:root:./patrol/.ssh/id_rsa:password123:prod db
```

### 2. check_groups.conf（检查组配置）
格式：`组标签:检查项1,检查项2,...`

示例：
```
# Web 服务器组
web:cpu_usage,memory_usage,disk_usage,process_count,docker_containers,docker_status

# 数据库服务器组
db:cpu_usage,memory_usage,disk_usage,process_count

# 所有服务器组
all:cpu_usage,memory_usage,disk_usage,process_count,docker_containers,docker_status
```

### 3. checks.conf（检查项配置）
格式：`名称:类型:命令 或 threshold:名称:警告,严重`

示例：
```
# CPU 使用率检查
cpu_usage:command:100 - \$(vmstat 1 2 | tail -n 1 | awk '{print \$15}')

# 内存使用率检查
memory_usage:command:\$(free -m | awk '/Mem:/ {print \$3/\$2*100}')

# 磁盘使用率检查
disk_usage:command:\$(df -h | awk '/\/dev\/[^\s]+\s+\/\s+/ {print \$5}' | sed 's/%//')

# 进程数量检查
process_count:command:\$(ps aux | wc -l)

# Docker 容器数量检查
docker_containers:command:\$(docker ps -q | wc -l)

# Docker 状态检查
docker_status:command:\$(docker info 2>/dev/null | grep 'Docker Engine' | wc -l)

# 阈值定义
threshold:cpu_usage:70,90
threshold:memory_usage:70,90
threshold:disk_usage:70,90
threshold:process_count:300,500
```

## 使用方法

### 基本用法
```bash
./patrol.sh
```

### 可选参数
- `-h, --help`：显示帮助信息
- `-g, --group GROUP`：仅巡检指定组的服务器
- `-o, --output FORMAT`：输出格式 (json|html|txt)，默认 all
- `--parallel NUM`：并发线程数，默认 5
- `-v, --verbose`：显示详细输出

### 示例

1. 巡检所有服务器，生成所有格式报告：
   ```bash
   ./patrol.sh
   ```

2. 仅巡检 prod 组的服务器：
   ```bash
   ./patrol.sh -g prod
   ```

3. 生成 JSON 格式报告：
   ```bash
   ./patrol.sh -o json
   ```

4. 使用 10 个并发线程：
   ```bash
   ./patrol.sh --parallel 10
   ```

## 报告格式说明

### JSON 报告
- 包含所有服务器的检查结果
- 每个检查项包含名称、值和状态
- 状态包括：normal、warn、serious

### HTML 报告
- 美观的网页格式
- 按服务器分组显示
- 不同状态使用不同颜色标识
- 可直接在浏览器中打开

### TXT 报告
- 简洁的文本格式
- 按服务器分组显示
- 适合命令行查看

## Web 端报告查看

1. **启动本地服务器**：
   ```bash
   cd web
   python3 -m http.server 8000
   ```

2. **访问 Web 界面**：
   - 打开浏览器，访问 `http://localhost:8000`
   - 查看最新的巡检报告
   - 支持报告历史查看

## 注意事项

1. **安全管控**：
   - 工具设计为离线使用，不依赖互联网
   - 密钥存储在项目目录中，便于管理
   - 配置文件中的密码以明文形式存储，建议设置适当的文件权限

2. **离线部署**：
   - 工具包含内置的 jq 工具，无需额外安装
   - 所有依赖均为系统自带工具

3. **性能优化**：
   - 支持并发执行，可根据服务器数量调整并发数
   - 远程执行脚本轻量，对服务器负载影响小

4. **维护建议**：
   - 定期更新配置文件，确保服务器信息准确
   - 定期检查阈值设置，确保告警合理
   - 定期清理日志和报告文件，避免磁盘空间占用

## 故障排除

- **无法连接到远程服务器**：检查网络连接、SSH 配置和服务器状态
- **远程脚本执行失败**：检查远程服务器的工具是否安装完整
- **报告生成失败**：检查 jq 工具是否正常工作
- **阈值告警不准确**：调整 checks.conf 中的阈值设置

## 扩展功能

- **添加新检查项**：在 checks.conf 中添加新的检查项定义
- **创建新检查组**：在 check_groups.conf 中创建新的检查组
- **添加新服务器**：在 servers.conf 中添加新的服务器信息
- **自定义报告模板**：修改 HTML 报告模板以满足特定需求
