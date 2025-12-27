# Suna 一键部署工具

自动化部署 Suna AI Agent 平台到 Linux 服务器。

## 快速开始

### 方式一：交互式安装（推荐）

```bash
# 下载并运行部署脚本
cd /opt/suna  # 或项目目录
sudo ./deploy/deploy.sh
```

部署脚本会引导您完成所有配置步骤。

### 方式二：使用配置文件

```bash
# 1. 复制配置模板
cp deploy/config.env.example deploy/config.env

# 2. 编辑配置文件
vim deploy/config.env

# 3. 运行自动部署
sudo ./deploy/deploy.sh --auto
```

### 方式三：远程快速安装

```bash
# 一行命令安装（需要 root 权限）
curl -fsSL https://raw.githubusercontent.com/GPT-Product-Group/suna-niuwei/main/deploy/quick-install.sh | sudo bash
```

## 目录结构

```
deploy/
├── deploy.sh              # 主部署脚本
├── quick-install.sh       # 远程快速安装脚本
├── config.env.example     # 配置模板
├── README.md              # 说明文档
└── scripts/
    ├── health-check.sh    # 健康检查脚本
    ├── backup.sh          # 备份脚本
    ├── upgrade.sh         # 升级脚本
    └── uninstall.sh       # 卸载脚本
```

## 命令行选项

```bash
sudo ./deploy/deploy.sh [选项]

选项:
  --auto          自动模式（需要 config.env）
  --skip-docker   跳过 Docker 安装
  --skip-nginx    跳过 Nginx 配置
  --skip-ssl      跳过 SSL 证书配置
  --config FILE   指定配置文件路径
  --install-dir   指定安装目录（默认: /opt/suna）
  --help, -h      显示帮助
```

## 部署后管理

部署完成后，可使用 `suna` 命令管理服务：

```bash
suna start      # 启动服务
suna stop       # 停止服务
suna restart    # 重启服务
suna status     # 查看状态
suna logs       # 查看日志
suna logs backend  # 查看后端日志
suna health     # 健康检查
suna update     # 更新服务
suna backup     # 备份数据
```

## 必需的外部服务

部署前需要准备以下服务的 API 密钥：

| 服务 | 用途 | 必需 | 获取地址 |
|------|------|------|----------|
| Supabase | 数据库、认证、存储 | ✅ | https://supabase.com |
| Anthropic 或 OpenAI | LLM API | ✅ | https://anthropic.com 或 https://openai.com |
| Tavily | 搜索服务 | ✅ | https://tavily.com |
| Firecrawl | 网页抓取 | ✅ | https://firecrawl.dev |
| RapidAPI | API 聚合 | ✅ | https://rapidapi.com |
| Daytona | Agent 沙箱 | ✅ | https://daytona.io |
| Sentry | 错误追踪 | ❌ | https://sentry.io |

## 系统要求

- **操作系统**: Ubuntu 20.04+ / Debian 11+
- **CPU**: 4+ 核心
- **内存**: 8+ GB
- **磁盘**: 50+ GB SSD
- **网络**: 开放 80, 443 端口

## 服务架构

```
                    ┌─────────────┐
                    │   Nginx     │
                    │  (80/443)   │
                    └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                │
    ┌──────────┐    ┌──────────┐           │
    │ Frontend │    │ Backend  │           │
    │  (3000)  │    │  (8000)  │           │
    │ Next.js  │    │ FastAPI  │           │
    └──────────┘    └────┬─────┘           │
                         │                 │
                    ┌────┴────┐            │
                    │  Redis  │◄───────────┘
                    │ (6379)  │    Worker
                    └─────────┘
```

## 故障排除

### 查看详细日志

```bash
# 所有服务日志
suna logs

# 特定服务
suna logs backend
suna logs worker
suna logs frontend

# Docker 容器详情
docker inspect suna-backend
```

### 常见问题

**Q: 容器无法启动**
```bash
# 查看容器日志
docker logs suna-backend

# 检查端口占用
sudo netstat -tlnp | grep -E '3000|8000|6379'
```

**Q: Nginx 502 错误**
```bash
# 检查后端是否运行
curl http://127.0.0.1:8000/v1/health

# 检查 Nginx 配置
sudo nginx -t
sudo tail -f /var/log/nginx/suna-*-error.log
```

**Q: Redis 连接失败**
```bash
# 测试 Redis
docker exec suna-redis redis-cli ping

# 查看 Redis 日志
docker logs suna-redis
```

### 重新部署

```bash
# 完全重建
cd /opt/suna
docker compose -f docker-compose.prod.yaml down -v
docker compose -f docker-compose.prod.yaml up -d --build
```

## 卸载

```bash
sudo ./deploy/scripts/uninstall.sh
```

## 更新

```bash
# 使用管理命令
suna update

# 或手动更新
cd /opt/suna
git pull
docker compose -f docker-compose.prod.yaml up -d --build
```

## 备份

```bash
# 手动备份
suna backup

# 或使用脚本
./deploy/scripts/backup.sh

# 设置自动备份 (每天凌晨 2 点)
(crontab -l; echo "0 2 * * * /opt/suna/deploy/scripts/backup.sh") | crontab -
```

## 许可证

Apache 2.0
