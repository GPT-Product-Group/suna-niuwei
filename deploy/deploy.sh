#!/bin/bash

#===============================================================================
# Suna AI Agent Platform - One-Click Deployment Script
# Target: Ubuntu 24.04 (Azure VM / Linux x86_64)
# Version: 1.0.0
#===============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 默认配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="${SUNA_INSTALL_DIR:-/opt/suna}"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# 部署模式
DEPLOY_MODE="${DEPLOY_MODE:-interactive}"  # interactive, auto, upgrade
SKIP_DOCKER="${SKIP_DOCKER:-false}"
SKIP_NGINX="${SKIP_NGINX:-false}"
SKIP_SSL="${SKIP_SSL:-false}"

#===============================================================================
# 工具函数
#===============================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} $1" >> "$LOG_FILE"
    echo -e "$1"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    log "${CYAN}${BOLD}==> $1${NC}"
}

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
  ____
 / ___| _   _ _ __   __ _
 \___ \| | | | '_ \ / _` |
  ___) | |_| | | | | (_| |
 |____/ \__,_|_| |_|\__,_|

 AI Agent Platform - Deployment Script
EOF
    echo -e "${NC}"
    echo "=============================================="
    echo "  Version: 1.0.0"
    echo "  Target:  Linux x86_64 (Ubuntu 24.04)"
    echo "=============================================="
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

check_os() {
    log_step "检查操作系统..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测操作系统"
        exit 1
    fi

    source /etc/os-release

    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log_warning "此脚本针对 Ubuntu/Debian 优化，其他系统可能需要手动调整"
    fi

    log_info "操作系统: $PRETTY_NAME"
    log_info "内核版本: $(uname -r)"
    log_info "架构: $(uname -m)"
}

check_resources() {
    log_step "检查系统资源..."

    # CPU
    local cpu_cores=$(nproc)
    log_info "CPU 核心数: $cpu_cores"
    if [[ $cpu_cores -lt 2 ]]; then
        log_warning "建议至少 4 核 CPU"
    fi

    # 内存
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    log_info "内存: ${total_mem}GB"
    if [[ $total_mem -lt 4 ]]; then
        log_error "内存不足，最低需要 4GB"
        exit 1
    fi

    # 磁盘
    local free_disk=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    log_info "可用磁盘空间: ${free_disk}GB"
    if [[ $free_disk -lt 20 ]]; then
        log_error "磁盘空间不足，最低需要 20GB"
        exit 1
    fi

    log_success "系统资源检查通过"
}

#===============================================================================
# 安装依赖
#===============================================================================

install_dependencies() {
    log_step "安装系统依赖..."

    apt-get update -qq
    apt-get install -y -qq \
        curl \
        wget \
        git \
        vim \
        htop \
        net-tools \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        jq \
        unzip \
        python3 \
        python3-pip \
        > /dev/null 2>&1

    log_success "系统依赖安装完成"
}

install_docker() {
    if [[ "$SKIP_DOCKER" == "true" ]]; then
        log_info "跳过 Docker 安装"
        return
    fi

    log_step "安装 Docker..."

    # 检查是否已安装
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        log_info "Docker 已安装: $docker_version"

        if [[ "$DEPLOY_MODE" != "auto" ]]; then
            read -p "是否重新安装 Docker? [y/N]: " reinstall
            if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
                return
            fi
        else
            return
        fi
    fi

    # 移除旧版本
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # 添加 Docker GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装 Docker
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1

    # 启动 Docker
    systemctl enable docker
    systemctl start docker

    # 配置 Docker daemon
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF

    systemctl restart docker

    log_success "Docker 安装完成: $(docker --version)"
}

#===============================================================================
# 配置向导
#===============================================================================

run_config_wizard() {
    log_step "配置向导"

    echo ""
    echo -e "${BOLD}请提供以下必要的配置信息:${NC}"
    echo "(如果已有配置文件 config.env，可按 Ctrl+C 退出后编辑该文件)"
    echo ""

    # 域名配置
    read -p "主域名 (例如: suna.example.com): " DOMAIN_NAME
    read -p "API 域名 (例如: api.suna.example.com, 留空使用 api.$DOMAIN_NAME): " API_DOMAIN
    API_DOMAIN="${API_DOMAIN:-api.$DOMAIN_NAME}"

    echo ""
    echo -e "${BOLD}Supabase 配置 (必填):${NC}"
    read -p "Supabase URL: " SUPABASE_URL
    read -p "Supabase Anon Key: " SUPABASE_ANON_KEY
    read -sp "Supabase Service Role Key: " SUPABASE_SERVICE_ROLE_KEY
    echo ""
    read -sp "Supabase JWT Secret: " SUPABASE_JWT_SECRET
    echo ""

    echo ""
    echo -e "${BOLD}LLM API 配置 (至少填写一个):${NC}"
    read -sp "Anthropic API Key (留空跳过): " ANTHROPIC_API_KEY
    echo ""
    read -sp "OpenAI API Key (留空跳过): " OPENAI_API_KEY
    echo ""

    echo ""
    echo -e "${BOLD}搜索服务配置 (必填):${NC}"
    read -sp "Tavily API Key: " TAVILY_API_KEY
    echo ""
    read -sp "Firecrawl API Key: " FIRECRAWL_API_KEY
    echo ""
    read -sp "Rapid API Key: " RAPID_API_KEY
    echo ""

    echo ""
    echo -e "${BOLD}Daytona 配置 (必填):${NC}"
    read -sp "Daytona API Key: " DAYTONA_API_KEY
    echo ""
    read -p "Daytona Target (us/eu) [us]: " DAYTONA_TARGET
    DAYTONA_TARGET="${DAYTONA_TARGET:-us}"

    echo ""
    echo -e "${BOLD}可选配置:${NC}"
    read -p "配置 SSL 证书? [Y/n]: " SETUP_SSL
    SETUP_SSL="${SETUP_SSL:-Y}"

    if [[ "$SETUP_SSL" =~ ^[Yy]$ ]]; then
        read -p "SSL 证书邮箱 (用于 Let's Encrypt): " SSL_EMAIL
    fi

    read -p "配置 Sentry 错误追踪? [y/N]: " SETUP_SENTRY
    if [[ "$SETUP_SENTRY" =~ ^[Yy]$ ]]; then
        read -p "Sentry DSN: " SENTRY_DSN
    fi

    # 生成加密密钥
    MCP_CREDENTIAL_ENCRYPTION_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>/dev/null || openssl rand -base64 32)
    KORTIX_ADMIN_API_KEY=$(openssl rand -hex 32)

    # 保存配置
    save_config

    log_success "配置已保存到 $CONFIG_FILE"
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
# Suna Deployment Configuration
# Generated: $(date)

# 域名配置
DOMAIN_NAME=${DOMAIN_NAME}
API_DOMAIN=${API_DOMAIN}
SSL_EMAIL=${SSL_EMAIL:-}

# Supabase
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
SUPABASE_JWT_SECRET=${SUPABASE_JWT_SECRET}

# LLM APIs
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}

# 搜索服务
TAVILY_API_KEY=${TAVILY_API_KEY}
FIRECRAWL_API_KEY=${FIRECRAWL_API_KEY}
RAPID_API_KEY=${RAPID_API_KEY}

# Daytona
DAYTONA_API_KEY=${DAYTONA_API_KEY}
DAYTONA_TARGET=${DAYTONA_TARGET}

# 安全
MCP_CREDENTIAL_ENCRYPTION_KEY=${MCP_CREDENTIAL_ENCRYPTION_KEY}
KORTIX_ADMIN_API_KEY=${KORTIX_ADMIN_API_KEY}

# 监控
SENTRY_DSN=${SENTRY_DSN:-}

# 部署选项
SETUP_SSL=${SETUP_SSL:-Y}
EOF

    chmod 600 "$CONFIG_FILE"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

validate_config() {
    log_step "验证配置..."

    local errors=0

    # 必填字段检查
    if [[ -z "$SUPABASE_URL" ]]; then
        log_error "缺少 SUPABASE_URL"
        ((errors++))
    fi

    if [[ -z "$SUPABASE_ANON_KEY" ]]; then
        log_error "缺少 SUPABASE_ANON_KEY"
        ((errors++))
    fi

    if [[ -z "$SUPABASE_SERVICE_ROLE_KEY" ]]; then
        log_error "缺少 SUPABASE_SERVICE_ROLE_KEY"
        ((errors++))
    fi

    if [[ -z "$ANTHROPIC_API_KEY" && -z "$OPENAI_API_KEY" ]]; then
        log_error "至少需要一个 LLM API Key (Anthropic 或 OpenAI)"
        ((errors++))
    fi

    if [[ -z "$TAVILY_API_KEY" ]]; then
        log_error "缺少 TAVILY_API_KEY"
        ((errors++))
    fi

    if [[ -z "$DAYTONA_API_KEY" ]]; then
        log_error "缺少 DAYTONA_API_KEY"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "配置验证失败，请检查 $CONFIG_FILE"
        exit 1
    fi

    log_success "配置验证通过"
}

#===============================================================================
# 项目部署
#===============================================================================

setup_project() {
    log_step "设置项目目录..."

    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/data"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/scripts"

    # 复制项目文件
    if [[ "$PROJECT_ROOT" != "$INSTALL_DIR" ]]; then
        log_info "复制项目文件到 $INSTALL_DIR..."
        rsync -av --exclude='.git' --exclude='node_modules' --exclude='__pycache__' \
            --exclude='.env' --exclude='*.log' \
            "$PROJECT_ROOT/" "$INSTALL_DIR/" > /dev/null
    fi

    log_success "项目目录设置完成"
}

create_env_files() {
    log_step "创建环境变量文件..."

    # 后端 .env
    cat > "$INSTALL_DIR/backend/.env" << EOF
# Suna Backend Configuration
# Generated by deploy.sh on $(date)

# 环境模式
ENV_MODE=production
LOG_LEVEL=INFO

# Supabase
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
SUPABASE_JWT_SECRET=${SUPABASE_JWT_SECRET}

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_SSL=false

# LLM APIs
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
OPENAI_API_KEY=${OPENAI_API_KEY:-}

# 搜索服务
TAVILY_API_KEY=${TAVILY_API_KEY}
FIRECRAWL_API_KEY=${FIRECRAWL_API_KEY}
RAPID_API_KEY=${RAPID_API_KEY}

# Daytona
DAYTONA_API_KEY=${DAYTONA_API_KEY}
DAYTONA_SERVER_URL=https://app.daytona.io/api
DAYTONA_TARGET=${DAYTONA_TARGET:-us}

# 安全
MCP_CREDENTIAL_ENCRYPTION_KEY=${MCP_CREDENTIAL_ENCRYPTION_KEY}

# 监控
SENTRY_DSN=${SENTRY_DSN:-}

# 管理
KORTIX_ADMIN_API_KEY=${KORTIX_ADMIN_API_KEY}
EOF

    chmod 600 "$INSTALL_DIR/backend/.env"

    # 前端 .env
    local backend_url="https://${API_DOMAIN:-api.$DOMAIN_NAME}/v1"
    local frontend_url="https://${DOMAIN_NAME}"

    if [[ -z "$DOMAIN_NAME" ]]; then
        backend_url="http://localhost:8000/v1"
        frontend_url="http://localhost:3000"
    fi

    cat > "$INSTALL_DIR/frontend/.env" << EOF
# Suna Frontend Configuration
# Generated by deploy.sh on $(date)

NEXT_PUBLIC_ENV_MODE=production
NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}
NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
NEXT_PUBLIC_BACKEND_URL=${backend_url}
NEXT_PUBLIC_URL=${frontend_url}
KORTIX_ADMIN_API_KEY=${KORTIX_ADMIN_API_KEY}
EOF

    chmod 600 "$INSTALL_DIR/frontend/.env"

    log_success "环境变量文件创建完成"
}

create_docker_compose() {
    log_step "创建 Docker Compose 配置..."

    cat > "$INSTALL_DIR/docker-compose.prod.yaml" << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:8-alpine
    container_name: suna-redis
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --maxmemory 4gb
      --maxmemory-policy allkeys-lru
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

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    image: suna-backend:latest
    container_name: suna-backend
    restart: unless-stopped
    env_file:
      - ./backend/.env
    ports:
      - "127.0.0.1:8000:8000"
    depends_on:
      redis:
        condition: service_healthy
      worker:
        condition: service_started
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - suna-network
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

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
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - suna-network
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
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
      start_period: 60s
    networks:
      - suna-network
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

volumes:
  redis_data:
    driver: local

networks:
  suna-network:
    driver: bridge
EOF

    log_success "Docker Compose 配置创建完成"
}

build_and_start() {
    log_step "构建和启动服务..."

    cd "$INSTALL_DIR"

    # 构建镜像
    log_info "构建 Docker 镜像 (这可能需要几分钟)..."
    docker compose -f docker-compose.prod.yaml build --no-cache 2>&1 | tee -a "$LOG_FILE"

    # 启动服务
    log_info "启动服务..."
    docker compose -f docker-compose.prod.yaml up -d

    # 等待服务健康
    log_info "等待服务启动..."
    local max_wait=120
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if docker compose -f docker-compose.prod.yaml ps | grep -q "healthy"; then
            break
        fi
        sleep 5
        ((waited+=5))
        echo -n "."
    done
    echo ""

    # 检查服务状态
    log_info "服务状态:"
    docker compose -f docker-compose.prod.yaml ps

    log_success "服务启动完成"
}

#===============================================================================
# Nginx 配置
#===============================================================================

setup_nginx() {
    if [[ "$SKIP_NGINX" == "true" ]]; then
        log_info "跳过 Nginx 配置"
        return
    fi

    log_step "配置 Nginx..."

    # 安装 Nginx
    apt-get install -y -qq nginx > /dev/null 2>&1

    # 创建配置
    cat > /etc/nginx/sites-available/suna << EOF
upstream suna_frontend {
    server 127.0.0.1:3000;
    keepalive 32;
}

upstream suna_backend {
    server 127.0.0.1:8000;
    keepalive 32;
}

# HTTP - 重定向到 HTTPS (如果启用 SSL)
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME} ${API_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# 前端
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN_NAME};

    ssl_certificate /etc/ssl/suna/fullchain.pem;
    ssl_certificate_key /etc/ssl/suna/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=63072000" always;

    client_max_body_size 100M;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    location / {
        proxy_pass http://suna_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# API
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${API_DOMAIN};

    ssl_certificate /etc/ssl/suna/fullchain.pem;
    ssl_certificate_key /etc/ssl/suna/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=63072000" always;

    client_max_body_size 100M;
    client_body_timeout 300s;

    location / {
        proxy_pass http://suna_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 1800s;
        proxy_read_timeout 1800s;
    }
}
EOF

    # 创建临时自签名证书 (后续可替换为 Let's Encrypt)
    mkdir -p /etc/ssl/suna
    if [[ ! -f /etc/ssl/suna/fullchain.pem ]]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/suna/privkey.pem \
            -out /etc/ssl/suna/fullchain.pem \
            -subj "/CN=${DOMAIN_NAME:-localhost}" 2>/dev/null
    fi

    # 启用配置
    ln -sf /etc/nginx/sites-available/suna /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # 测试并重载
    nginx -t
    systemctl enable nginx
    systemctl reload nginx

    log_success "Nginx 配置完成"
}

setup_ssl() {
    if [[ "$SKIP_SSL" == "true" ]] || [[ ! "$SETUP_SSL" =~ ^[Yy]$ ]]; then
        log_info "跳过 SSL 证书配置"
        return
    fi

    if [[ -z "$DOMAIN_NAME" ]] || [[ -z "$SSL_EMAIL" ]]; then
        log_warning "未提供域名或邮箱，跳过 SSL 配置"
        return
    fi

    log_step "配置 Let's Encrypt SSL 证书..."

    # 安装 Certbot
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1

    mkdir -p /var/www/certbot

    # 获取证书
    certbot certonly --webroot \
        -w /var/www/certbot \
        -d "$DOMAIN_NAME" \
        -d "$API_DOMAIN" \
        --email "$SSL_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --non-interactive

    # 更新 Nginx 配置使用真实证书
    sed -i "s|/etc/ssl/suna/|/etc/letsencrypt/live/${DOMAIN_NAME}/|g" /etc/nginx/sites-available/suna

    # 设置自动续期
    systemctl enable certbot.timer
    systemctl start certbot.timer

    nginx -t && systemctl reload nginx

    log_success "SSL 证书配置完成"
}

#===============================================================================
# Systemd 服务
#===============================================================================

setup_systemd() {
    log_step "配置 Systemd 服务..."

    cat > /etc/systemd/system/suna.service << EOF
[Unit]
Description=Suna AI Agent Platform
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yaml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yaml down
ExecReload=/usr/bin/docker compose -f docker-compose.prod.yaml restart
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable suna.service

    log_success "Systemd 服务配置完成"
}

#===============================================================================
# 管理脚本
#===============================================================================

create_management_scripts() {
    log_step "创建管理脚本..."

    # suna 命令行工具
    cat > /usr/local/bin/suna << 'SCRIPT'
#!/bin/bash

INSTALL_DIR="/opt/suna"
COMPOSE_FILE="docker-compose.prod.yaml"

case "$1" in
    start)
        echo "启动 Suna 服务..."
        cd "$INSTALL_DIR" && docker compose -f "$COMPOSE_FILE" up -d
        ;;
    stop)
        echo "停止 Suna 服务..."
        cd "$INSTALL_DIR" && docker compose -f "$COMPOSE_FILE" down
        ;;
    restart)
        echo "重启 Suna 服务..."
        cd "$INSTALL_DIR" && docker compose -f "$COMPOSE_FILE" restart
        ;;
    status)
        cd "$INSTALL_DIR" && docker compose -f "$COMPOSE_FILE" ps
        ;;
    logs)
        shift
        cd "$INSTALL_DIR" && docker compose -f "$COMPOSE_FILE" logs -f "$@"
        ;;
    health)
        echo "检查服务健康状态..."
        echo ""
        echo "Backend API:"
        curl -s http://127.0.0.1:8000/v1/health | jq . 2>/dev/null || echo "  不可用"
        echo ""
        echo "Frontend:"
        curl -s -o /dev/null -w "  HTTP Status: %{http_code}\n" http://127.0.0.1:3000
        echo ""
        echo "Redis:"
        docker exec suna-redis redis-cli ping 2>/dev/null || echo "  不可用"
        ;;
    update)
        echo "更新 Suna..."
        cd "$INSTALL_DIR"
        git pull
        docker compose -f "$COMPOSE_FILE" build
        docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
        ;;
    backup)
        echo "备份数据..."
        BACKUP_DIR="$INSTALL_DIR/backups"
        DATE=$(date +%Y%m%d_%H%M%S)
        mkdir -p "$BACKUP_DIR"
        docker exec suna-redis redis-cli BGSAVE
        sleep 3
        docker cp suna-redis:/data/dump.rdb "$BACKUP_DIR/redis_$DATE.rdb"
        gzip "$BACKUP_DIR/redis_$DATE.rdb"
        echo "备份完成: $BACKUP_DIR/redis_$DATE.rdb.gz"
        ;;
    *)
        echo "Suna 管理工具"
        echo ""
        echo "用法: suna <命令>"
        echo ""
        echo "命令:"
        echo "  start    启动所有服务"
        echo "  stop     停止所有服务"
        echo "  restart  重启所有服务"
        echo "  status   查看服务状态"
        echo "  logs     查看日志 (可选: backend, frontend, worker, redis)"
        echo "  health   检查服务健康状态"
        echo "  update   更新并重启服务"
        echo "  backup   备份 Redis 数据"
        ;;
esac
SCRIPT

    chmod +x /usr/local/bin/suna

    log_success "管理脚本创建完成 (使用 'suna' 命令管理)"
}

#===============================================================================
# 完成部署
#===============================================================================

print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}=============================================="
    echo "  Suna 部署完成!"
    echo "==============================================${NC}"
    echo ""
    echo -e "${BOLD}访问地址:${NC}"
    if [[ -n "$DOMAIN_NAME" ]]; then
        echo "  前端: https://${DOMAIN_NAME}"
        echo "  API:  https://${API_DOMAIN}/v1"
    else
        echo "  前端: http://localhost:3000"
        echo "  API:  http://localhost:8000/v1"
    fi
    echo ""
    echo -e "${BOLD}管理命令:${NC}"
    echo "  suna start    - 启动服务"
    echo "  suna stop     - 停止服务"
    echo "  suna status   - 查看状态"
    echo "  suna logs     - 查看日志"
    echo "  suna health   - 健康检查"
    echo ""
    echo -e "${BOLD}配置文件:${NC}"
    echo "  后端: ${INSTALL_DIR}/backend/.env"
    echo "  前端: ${INSTALL_DIR}/frontend/.env"
    echo ""
    echo -e "${BOLD}日志位置:${NC}"
    echo "  部署日志: ${LOG_FILE}"
    echo "  应用日志: suna logs"
    echo ""
    echo -e "${YELLOW}注意: 首次部署后请检查服务状态: suna health${NC}"
    echo ""
}

#===============================================================================
# 主函数
#===============================================================================

main() {
    print_banner

    # 检查权限
    check_root

    # 初始化日志
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Suna Deployment Started: $(date) ===" > "$LOG_FILE"

    # 系统检查
    check_os
    check_resources

    # 安装依赖
    install_dependencies
    install_docker

    # 配置
    if ! load_config; then
        if [[ "$DEPLOY_MODE" == "auto" ]]; then
            log_error "自动模式需要配置文件: $CONFIG_FILE"
            exit 1
        fi
        run_config_wizard
    fi

    validate_config

    # 部署
    setup_project
    create_env_files
    create_docker_compose
    build_and_start

    # Nginx 和 SSL
    if [[ -n "$DOMAIN_NAME" ]]; then
        setup_nginx
        setup_ssl
    fi

    # 系统服务
    setup_systemd
    create_management_scripts

    # 完成
    print_summary

    log_success "部署完成!"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            DEPLOY_MODE="auto"
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER="true"
            shift
            ;;
        --skip-nginx)
            SKIP_NGINX="true"
            shift
            ;;
        --skip-ssl)
            SKIP_SSL="true"
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Suna 一键部署脚本"
            echo ""
            echo "用法: sudo ./deploy.sh [选项]"
            echo ""
            echo "选项:"
            echo "  --auto          自动模式 (需要 config.env)"
            echo "  --skip-docker   跳过 Docker 安装"
            echo "  --skip-nginx    跳过 Nginx 配置"
            echo "  --skip-ssl      跳过 SSL 证书配置"
            echo "  --config FILE   指定配置文件路径"
            echo "  --install-dir   指定安装目录"
            echo "  --help, -h      显示帮助"
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            exit 1
            ;;
    esac
done

# 运行主函数
main
