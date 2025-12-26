# Suna (Kortix AI Agent Platform) - Linux 部署方案

## 目标环境

- **操作系统**: Linux teachSuna2 6.14.0-1017-azure (Ubuntu 24.04)
- **架构**: x86_64
- **平台**: Azure VM

---

## 目录

1. [系统要求](#1-系统要求)
2. [系统准备](#2-系统准备)
3. [Docker 环境安装](#3-docker-环境安装)
4. [项目部署](#4-项目部署)
5. [环境变量配置](#5-环境变量配置)
6. [Supabase 数据库设置](#6-supabase-数据库设置)
7. [服务启动与管理](#7-服务启动与管理)
8. [Nginx 反向代理配置](#8-nginx-反向代理配置)
9. [SSL 证书配置](#9-ssl-证书配置)
10. [防火墙配置](#10-防火墙配置)
11. [监控与日志](#11-监控与日志)
12. [备份策略](#12-备份策略)
13. [故障排除](#13-故障排除)
14. [性能优化](#14-性能优化)

---

## 1. 系统要求

### 硬件要求

| 资源 | 最低配置 | 推荐配置 |
|------|---------|---------|
| CPU | 4 vCPU | 8+ vCPU |
| 内存 | 8 GB | 16+ GB |
| 磁盘 | 50 GB SSD | 100+ GB SSD |
| 网络 | 100 Mbps | 1 Gbps |

### 软件要求

| 组件 | 版本 |
|------|------|
| Docker | 24.0+ |
| Docker Compose | v2.20+ |
| Git | 2.40+ |
| Nginx | 1.24+ (可选，反向代理) |

### 端口要求

| 端口 | 服务 | 说明 |
|------|------|------|
| 80 | HTTP | 重定向到 HTTPS |
| 443 | HTTPS | 主服务入口 |
| 3000 | Frontend | Next.js 前端 |
| 8000 | Backend | FastAPI 后端 |
| 6379 | Redis | 仅内部访问 |

---

## 2. 系统准备

### 2.1 更新系统

```bash
# 更新系统包
sudo apt update && sudo apt upgrade -y

# 安装必要工具
sudo apt install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    net-tools \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common
```

### 2.2 设置时区

```bash
# 设置时区为 UTC (推荐生产环境)
sudo timedatectl set-timezone UTC

# 或设置为中国时区
# sudo timedatectl set-timezone Asia/Shanghai
```

### 2.3 创建部署用户 (可选但推荐)

```bash
# 创建专用部署用户
sudo useradd -m -s /bin/bash suna
sudo usermod -aG sudo suna
sudo usermod -aG docker suna

# 切换到部署用户
sudo su - suna
```

### 2.4 调整系统限制

```bash
# 编辑 /etc/security/limits.conf
sudo tee -a /etc/security/limits.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# 编辑 /etc/sysctl.conf 优化网络
sudo tee -a /etc/sysctl.conf << 'EOF'
# 网络优化
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535

# 内存优化
vm.swappiness = 10
vm.overcommit_memory = 1
EOF

# 应用配置
sudo sysctl -p
```

---

## 3. Docker 环境安装

### 3.1 安装 Docker

```bash
# 移除旧版本
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# 添加 Docker 官方 GPG 密钥
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 添加 Docker 仓库
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 启动并启用 Docker
sudo systemctl enable docker
sudo systemctl start docker

# 将当前用户添加到 docker 组
sudo usermod -aG docker $USER
newgrp docker

# 验证安装
docker --version
docker compose version
```

### 3.2 配置 Docker 守护进程

```bash
# 创建 Docker 配置
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
EOF

# 重启 Docker
sudo systemctl restart docker
```

---

## 4. 项目部署

### 4.1 克隆项目

```bash
# 创建应用目录
sudo mkdir -p /opt/suna
sudo chown $USER:$USER /opt/suna
cd /opt/suna

# 克隆项目
git clone https://github.com/GPT-Product-Group/suna-niuwei.git .

# 或者如果已有代码，直接复制
# cp -r /path/to/suna-niuwei/* /opt/suna/
```

### 4.2 创建生产环境 Docker Compose 配置

```bash
# 创建生产环境配置文件
cat > /opt/suna/docker-compose.prod.yaml << 'EOF'
version: '3.8'

services:
  # Redis 缓存和消息队列
  redis:
    image: redis:8-alpine
    container_name: suna-redis
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --maxmemory 4gb
      --maxmemory-policy allkeys-lru
      --bind 0.0.0.0
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - suna-network
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

  # 后端 API 服务
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    image: suna-backend:latest
    container_name: suna-backend
    restart: unless-stopped
    env_file:
      - ./backend/.env
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_SSL=false
    ports:
      - "127.0.0.1:8000:8000"
    depends_on:
      redis:
        condition: service_healthy
      worker:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    networks:
      - suna-network
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

  # 后台 Worker 服务
  worker:
    build:
      context: ./backend
      dockerfile: Dockerfile
    image: suna-backend:latest
    container_name: suna-worker
    restart: unless-stopped
    command: python -m dramatiq run_agent_background --processes 4 --threads 4
    env_file:
      - ./backend/.env
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_SSL=false
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "worker_health.py"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 30s
    networks:
      - suna-network
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

  # 前端服务
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args:
        - NEXT_PUBLIC_BACKEND_URL=${NEXT_PUBLIC_BACKEND_URL:-http://localhost:8000/v1}
        - NEXT_PUBLIC_URL=${NEXT_PUBLIC_URL:-http://localhost:3000}
        - NEXT_PUBLIC_ENV_MODE=${NEXT_PUBLIC_ENV_MODE:-production}
    image: suna-frontend:latest
    container_name: suna-frontend
    restart: unless-stopped
    env_file:
      - ./frontend/.env
    ports:
      - "127.0.0.1:3000:3000"
    depends_on:
      backend:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    networks:
      - suna-network
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

volumes:
  redis_data:
    driver: local

networks:
  suna-network:
    driver: bridge
EOF
```

### 4.3 创建目录结构

```bash
# 创建必要的目录
mkdir -p /opt/suna/logs
mkdir -p /opt/suna/data
mkdir -p /opt/suna/backups
mkdir -p /opt/suna/ssl

# 设置权限
chmod 755 /opt/suna/logs
chmod 755 /opt/suna/data
chmod 700 /opt/suna/ssl
```

---

## 5. 环境变量配置

### 5.1 后端环境变量

```bash
# 复制示例配置
cp /opt/suna/backend/.env.example /opt/suna/backend/.env

# 编辑后端环境变量
cat > /opt/suna/backend/.env << 'EOF'
# ============================================
# Suna Backend 生产环境配置
# ============================================

# 环境模式
ENV_MODE=production
LOG_LEVEL=INFO

# ============================================
# Supabase 配置 (必填)
# ============================================
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_JWT_SECRET=your-jwt-secret

# ============================================
# Redis 配置
# ============================================
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_SSL=false

# ============================================
# LLM API 密钥 (至少配置一个)
# ============================================
ANTHROPIC_API_KEY=sk-ant-xxxxx
OPENAI_API_KEY=sk-xxxxx
# GROQ_API_KEY=
# OPENROUTER_API_KEY=
# GEMINI_API_KEY=
# XAI_API_KEY=

# ============================================
# 搜索和网页服务 (必填)
# ============================================
TAVILY_API_KEY=tvly-xxxxx
FIRECRAWL_API_KEY=fc-xxxxx
RAPID_API_KEY=xxxxx

# ============================================
# Agent Sandbox (Daytona) 配置 (必填)
# ============================================
DAYTONA_API_KEY=your-daytona-key
DAYTONA_SERVER_URL=https://app.daytona.io/api
DAYTONA_TARGET=us

# ============================================
# 安全配置
# ============================================
# 生成方式: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
MCP_CREDENTIAL_ENCRYPTION_KEY=your-32-byte-base64-key

# ============================================
# 监控配置 (可选但推荐)
# ============================================
SENTRY_DSN=https://xxxxx@sentry.io/xxxxx
LANGFUSE_PUBLIC_KEY=pk-xxxxx
LANGFUSE_SECRET_KEY=sk-xxxxx
LANGFUSE_HOST=https://cloud.langfuse.com

# ============================================
# 计费配置 (可选)
# ============================================
# STRIPE_SECRET_KEY=sk_live_xxxxx
# STRIPE_WEBHOOK_SECRET=whsec_xxxxx
# STRIPE_DEFAULT_PLAN_ID=price_xxxxx
# STRIPE_DEFAULT_TRIAL_DAYS=7

# ============================================
# 其他集成 (可选)
# ============================================
# COMPOSIO_API_KEY=
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=
# EXA_API_KEY=
# REPLICATE_API_TOKEN=
# MAILTRAP_API_TOKEN=

# ============================================
# 管理配置
# ============================================
KORTIX_ADMIN_API_KEY=your-admin-api-key
EOF

# 设置安全权限
chmod 600 /opt/suna/backend/.env
```

### 5.2 前端环境变量

```bash
# 复制示例配置
cp /opt/suna/frontend/.env.example /opt/suna/frontend/.env

# 编辑前端环境变量
cat > /opt/suna/frontend/.env << 'EOF'
# ============================================
# Suna Frontend 生产环境配置
# ============================================

# 环境模式
NEXT_PUBLIC_ENV_MODE=production

# Supabase 配置
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key

# 服务 URL (根据实际域名修改)
NEXT_PUBLIC_BACKEND_URL=https://api.your-domain.com/v1
NEXT_PUBLIC_URL=https://your-domain.com

# Google OAuth (可选)
# NEXT_PUBLIC_GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com

# 分析 (可选)
# NEXT_PUBLIC_POSTHOG_KEY=phc_xxxxx

# 管理
KORTIX_ADMIN_API_KEY=your-admin-api-key
EOF

# 设置安全权限
chmod 600 /opt/suna/frontend/.env
```

### 5.3 生成加密密钥

```bash
# 安装 Python cryptography 库（如果未安装）
pip3 install cryptography

# 生成 Fernet 加密密钥
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
# 将输出的密钥复制到 MCP_CREDENTIAL_ENCRYPTION_KEY
```

---

## 6. Supabase 数据库设置

### 6.1 创建 Supabase 项目

1. 访问 [Supabase](https://supabase.com) 并创建账号
2. 创建新项目，选择最近的区域
3. 记录以下信息：
   - Project URL
   - Anon/Public Key
   - Service Role Key
   - JWT Secret

### 6.2 运行数据库迁移

```bash
# 安装 Supabase CLI
npm install -g supabase

# 登录 Supabase
supabase login

# 链接到远程项目
cd /opt/suna/backend
supabase link --project-ref your-project-ref

# 推送数据库迁移
supabase db push

# 运行性能优化 SQL (可选但推荐)
# 在 Supabase Dashboard > SQL Editor 中运行:
# /opt/suna/backend/supabase/RUN_VIA_PSQL_index_optimisations.sql
```

### 6.3 配置 Supabase 存储

在 Supabase Dashboard 中：

1. 进入 **Storage** 页面
2. 创建 bucket: `agentpress`
3. 设置文件大小限制: 50 MiB
4. 配置允许的 MIME 类型

### 6.4 配置认证

在 Supabase Dashboard 中：

1. 进入 **Authentication > Settings**
2. 配置站点 URL: `https://your-domain.com`
3. 添加重定向 URL: `https://your-domain.com/*`
4. 启用需要的认证提供商 (Email, Google 等)

---

## 7. 服务启动与管理

### 7.1 构建镜像

```bash
cd /opt/suna

# 构建所有镜像
docker compose -f docker-compose.prod.yaml build

# 或分别构建
docker compose -f docker-compose.prod.yaml build backend
docker compose -f docker-compose.prod.yaml build frontend
```

### 7.2 启动服务

```bash
# 启动所有服务
docker compose -f docker-compose.prod.yaml up -d

# 查看服务状态
docker compose -f docker-compose.prod.yaml ps

# 查看日志
docker compose -f docker-compose.prod.yaml logs -f

# 查看特定服务日志
docker compose -f docker-compose.prod.yaml logs -f backend
docker compose -f docker-compose.prod.yaml logs -f worker
docker compose -f docker-compose.prod.yaml logs -f frontend
```

### 7.3 服务管理命令

```bash
# 停止服务
docker compose -f docker-compose.prod.yaml down

# 重启单个服务
docker compose -f docker-compose.prod.yaml restart backend

# 更新并重启
docker compose -f docker-compose.prod.yaml pull
docker compose -f docker-compose.prod.yaml up -d --remove-orphans

# 清理旧镜像
docker image prune -f
```

### 7.4 创建 Systemd 服务 (开机自启)

```bash
sudo tee /etc/systemd/system/suna.service << 'EOF'
[Unit]
Description=Suna AI Agent Platform
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/suna
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yaml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yaml down
ExecReload=/usr/bin/docker compose -f docker-compose.prod.yaml restart
TimeoutStartSec=300
User=root

[Install]
WantedBy=multi-user.target
EOF

# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable suna.service

# 管理服务
sudo systemctl start suna
sudo systemctl status suna
sudo systemctl stop suna
```

---

## 8. Nginx 反向代理配置

### 8.1 安装 Nginx

```bash
sudo apt install -y nginx
sudo systemctl enable nginx
```

### 8.2 配置 Nginx

```bash
# 创建 Suna 配置
sudo tee /etc/nginx/sites-available/suna << 'EOF'
# 上游服务器配置
upstream suna_frontend {
    server 127.0.0.1:3000;
    keepalive 32;
}

upstream suna_backend {
    server 127.0.0.1:8000;
    keepalive 32;
}

# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name your-domain.com api.your-domain.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# 前端 HTTPS 配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name your-domain.com;

    # SSL 证书 (使用 Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/your-domain.com/chain.pem;

    # SSL 配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    # 日志
    access_log /var/log/nginx/suna-frontend-access.log;
    error_log /var/log/nginx/suna-frontend-error.log;

    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

    # 客户端设置
    client_max_body_size 100M;
    client_body_timeout 120s;

    # 前端代理
    location / {
        proxy_pass http://suna_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 静态资源缓存
    location /_next/static {
        proxy_pass http://suna_frontend;
        proxy_cache_valid 200 60d;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }
}

# 后端 API HTTPS 配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.your-domain.com;

    # SSL 证书
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/your-domain.com/chain.pem;

    # SSL 配置 (同上)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    # CORS 头 (根据需要调整)
    add_header Access-Control-Allow-Origin "https://your-domain.com" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With" always;
    add_header Access-Control-Allow-Credentials "true" always;

    # 日志
    access_log /var/log/nginx/suna-api-access.log;
    error_log /var/log/nginx/suna-api-error.log;

    # 客户端设置
    client_max_body_size 100M;
    client_body_timeout 300s;

    # 后端 API 代理
    location / {
        # 处理 OPTIONS 预检请求
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin "https://your-domain.com" always;
            add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
            add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Requested-With" always;
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type 'text/plain; charset=utf-8';
            add_header Content-Length 0;
            return 204;
        }

        proxy_pass http://suna_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # 长连接支持 (用于 Agent 执行)
        proxy_connect_timeout 300s;
        proxy_send_timeout 1800s;
        proxy_read_timeout 1800s;
    }

    # 健康检查端点
    location /v1/health {
        proxy_pass http://suna_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 5s;
    }
}
EOF

# 启用配置
sudo ln -sf /etc/nginx/sites-available/suna /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 测试配置
sudo nginx -t

# 重载 Nginx
sudo systemctl reload nginx
```

---

## 9. SSL 证书配置

### 9.1 使用 Let's Encrypt (推荐)

```bash
# 安装 Certbot
sudo apt install -y certbot python3-certbot-nginx

# 创建 webroot 目录
sudo mkdir -p /var/www/certbot

# 获取证书 (先暂时禁用 SSL 配置)
sudo certbot certonly --webroot \
    -w /var/www/certbot \
    -d your-domain.com \
    -d api.your-domain.com \
    --email your-email@example.com \
    --agree-tos \
    --no-eff-email

# 或使用 nginx 插件 (更简单)
sudo certbot --nginx \
    -d your-domain.com \
    -d api.your-domain.com \
    --email your-email@example.com \
    --agree-tos \
    --no-eff-email

# 设置自动续期
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# 测试续期
sudo certbot renew --dry-run
```

### 9.2 手动证书 (如果使用其他 CA)

```bash
# 创建证书目录
sudo mkdir -p /etc/ssl/suna

# 复制证书文件
sudo cp your-cert.crt /etc/ssl/suna/fullchain.pem
sudo cp your-key.key /etc/ssl/suna/privkey.pem

# 设置权限
sudo chmod 600 /etc/ssl/suna/privkey.pem
sudo chmod 644 /etc/ssl/suna/fullchain.pem

# 更新 Nginx 配置中的证书路径
```

---

## 10. 防火墙配置

### 10.1 UFW 配置

```bash
# 安装 UFW (如果未安装)
sudo apt install -y ufw

# 默认规则
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 允许 SSH
sudo ufw allow 22/tcp

# 允许 HTTP 和 HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 启用防火墙
sudo ufw enable

# 查看状态
sudo ufw status verbose
```

### 10.2 Azure 网络安全组 (NSG)

在 Azure Portal 中配置入站规则：

| 优先级 | 名称 | 端口 | 协议 | 来源 | 操作 |
|-------|------|------|------|------|------|
| 100 | SSH | 22 | TCP | Your IP | 允许 |
| 200 | HTTP | 80 | TCP | Any | 允许 |
| 300 | HTTPS | 443 | TCP | Any | 允许 |

---

## 11. 监控与日志

### 11.1 Docker 日志管理

```bash
# 查看所有服务日志
docker compose -f /opt/suna/docker-compose.prod.yaml logs -f --tail=100

# 查看特定服务
docker compose -f /opt/suna/docker-compose.prod.yaml logs -f backend --tail=100

# 导出日志
docker compose -f /opt/suna/docker-compose.prod.yaml logs > /opt/suna/logs/full-$(date +%Y%m%d).log
```

### 11.2 创建监控脚本

```bash
# 创建健康检查脚本
cat > /opt/suna/scripts/health-check.sh << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================"
echo "Suna 服务健康检查 - $(date)"
echo "======================================"

# 检查 Docker 服务
echo -n "Docker 服务: "
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}运行中${NC}"
else
    echo -e "${RED}已停止${NC}"
fi

# 检查各容器状态
echo ""
echo "容器状态:"
cd /opt/suna
docker compose -f docker-compose.prod.yaml ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# 检查 Backend API
echo ""
echo -n "Backend API: "
if curl -sf http://127.0.0.1:8000/v1/health > /dev/null 2>&1; then
    echo -e "${GREEN}健康${NC}"
else
    echo -e "${RED}不可用${NC}"
fi

# 检查 Frontend
echo -n "Frontend: "
if curl -sf http://127.0.0.1:3000 > /dev/null 2>&1; then
    echo -e "${GREEN}健康${NC}"
else
    echo -e "${RED}不可用${NC}"
fi

# 检查 Redis
echo -n "Redis: "
if docker exec suna-redis redis-cli ping > /dev/null 2>&1; then
    echo -e "${GREEN}健康${NC}"
else
    echo -e "${RED}不可用${NC}"
fi

# 系统资源
echo ""
echo "系统资源:"
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
echo "内存: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo "磁盘: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"

echo ""
echo "======================================"
EOF

chmod +x /opt/suna/scripts/health-check.sh
```

### 11.3 设置定时健康检查

```bash
# 添加 cron 任务
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/suna/scripts/health-check.sh >> /opt/suna/logs/health-check.log 2>&1") | crontab -
```

### 11.4 配置日志轮转

```bash
sudo tee /etc/logrotate.d/suna << 'EOF'
/opt/suna/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}

/var/log/nginx/suna-*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}
EOF
```

---

## 12. 备份策略

### 12.1 Redis 备份脚本

```bash
cat > /opt/suna/scripts/backup-redis.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/suna/backups/redis"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

# 创建 Redis 备份
docker exec suna-redis redis-cli BGSAVE
sleep 5

# 复制备份文件
docker cp suna-redis:/data/dump.rdb $BACKUP_DIR/redis_$DATE.rdb

# 压缩
gzip $BACKUP_DIR/redis_$DATE.rdb

# 删除旧备份
find $BACKUP_DIR -name "*.rdb.gz" -mtime +$RETENTION_DAYS -delete

echo "Redis backup completed: redis_$DATE.rdb.gz"
EOF

chmod +x /opt/suna/scripts/backup-redis.sh
```

### 12.2 配置文件备份

```bash
cat > /opt/suna/scripts/backup-config.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/suna/backups/config"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

mkdir -p $BACKUP_DIR

# 备份配置文件
tar -czf $BACKUP_DIR/config_$DATE.tar.gz \
    /opt/suna/backend/.env \
    /opt/suna/frontend/.env \
    /opt/suna/docker-compose.prod.yaml \
    /etc/nginx/sites-available/suna \
    2>/dev/null

# 删除旧备份
find $BACKUP_DIR -name "config_*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Config backup completed: config_$DATE.tar.gz"
EOF

chmod +x /opt/suna/scripts/backup-config.sh
```

### 12.3 设置自动备份

```bash
# 添加备份 cron 任务
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/suna/scripts/backup-redis.sh >> /opt/suna/logs/backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 /opt/suna/scripts/backup-config.sh >> /opt/suna/logs/backup.log 2>&1") | crontab -
```

---

## 13. 故障排除

### 13.1 常见问题

#### 容器无法启动

```bash
# 查看详细日志
docker compose -f docker-compose.prod.yaml logs backend

# 检查容器详情
docker inspect suna-backend

# 检查端口占用
sudo netstat -tlnp | grep -E '3000|8000|6379'
```

#### Redis 连接失败

```bash
# 测试 Redis 连接
docker exec suna-redis redis-cli ping

# 检查 Redis 日志
docker logs suna-redis

# 检查 Redis 内存使用
docker exec suna-redis redis-cli INFO memory
```

#### Backend 健康检查失败

```bash
# 手动测试健康检查
curl -v http://127.0.0.1:8000/v1/health

# 检查后端日志
docker logs suna-backend --tail=100

# 进入容器调试
docker exec -it suna-backend /bin/bash
```

#### Nginx 502 错误

```bash
# 检查上游服务是否运行
curl http://127.0.0.1:3000
curl http://127.0.0.1:8000/v1/health

# 检查 Nginx 日志
tail -f /var/log/nginx/suna-*-error.log

# 测试 Nginx 配置
sudo nginx -t
```

### 13.2 重启服务

```bash
# 重启所有服务
cd /opt/suna
docker compose -f docker-compose.prod.yaml restart

# 强制重建
docker compose -f docker-compose.prod.yaml up -d --force-recreate

# 完全重置 (谨慎使用)
docker compose -f docker-compose.prod.yaml down -v
docker compose -f docker-compose.prod.yaml up -d
```

### 13.3 紧急回滚

```bash
# 回滚到上一版本镜像
docker compose -f docker-compose.prod.yaml pull
docker compose -f docker-compose.prod.yaml up -d --force-recreate

# 或指定版本
# 编辑 docker-compose.prod.yaml 中的镜像标签
# 然后重新启动
```

---

## 14. 性能优化

### 14.1 Docker 资源限制调整

根据服务器规格调整 `docker-compose.prod.yaml` 中的资源限制：

```yaml
# 8 vCPU, 16GB RAM 服务器建议配置
deploy:
  resources:
    limits:
      memory: 4G
      cpus: '2'
    reservations:
      memory: 1G
      cpus: '0.5'
```

### 14.2 Nginx 优化

```bash
# 编辑 /etc/nginx/nginx.conf
sudo tee /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    # 基础设置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # 日志
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

    # 缓冲区
    client_body_buffer_size 10K;
    client_header_buffer_size 1k;
    client_max_body_size 100m;
    large_client_header_buffers 4 32k;

    # 超时
    client_body_timeout 120;
    client_header_timeout 120;
    send_timeout 120;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

sudo systemctl reload nginx
```

### 14.3 Redis 优化

Redis 配置已在 docker-compose 中优化，主要参数：
- `maxmemory 4gb` - 最大内存限制
- `maxmemory-policy allkeys-lru` - LRU 淘汰策略
- `appendonly yes` - AOF 持久化

---

## 快速部署检查清单

### 部署前
- [ ] 服务器满足硬件要求
- [ ] Docker 和 Docker Compose 已安装
- [ ] Supabase 项目已创建并配置
- [ ] 必需的 API 密钥已获取 (LLM, Tavily, Firecrawl, Daytona)
- [ ] 域名已配置 DNS 解析

### 部署中
- [ ] 项目代码已克隆到 /opt/suna
- [ ] 环境变量文件已配置 (.env)
- [ ] Docker 镜像已构建
- [ ] 服务已启动并健康
- [ ] Nginx 反向代理已配置
- [ ] SSL 证书已安装

### 部署后
- [ ] 所有健康检查通过
- [ ] 前端可以正常访问
- [ ] API 可以正常响应
- [ ] 备份任务已配置
- [ ] 监控已启用
- [ ] 防火墙规则已配置

---

## 支持与维护

### 日常维护命令

```bash
# 查看服务状态
/opt/suna/scripts/health-check.sh

# 查看日志
docker compose -f /opt/suna/docker-compose.prod.yaml logs -f

# 更新服务
cd /opt/suna && git pull && docker compose -f docker-compose.prod.yaml up -d --build

# 清理磁盘空间
docker system prune -f
docker volume prune -f
```

### 获取帮助

- GitHub Issues: https://github.com/GPT-Product-Group/suna-niuwei/issues
- 项目文档: 参考仓库内的 README 文件

---

*文档版本: 1.0*
*最后更新: 2025-12-26*
*目标环境: Ubuntu 24.04 (Azure VM)*
