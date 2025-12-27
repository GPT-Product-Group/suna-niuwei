#!/bin/bash

#===============================================================================
# Suna 升级脚本
#===============================================================================

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

INSTALL_DIR="${SUNA_INSTALL_DIR:-/opt/suna}"
COMPOSE_FILE="docker-compose.prod.yaml"
BACKUP_BEFORE_UPGRADE="${BACKUP_BEFORE_UPGRADE:-true}"

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

echo ""
echo -e "${BOLD}======================================"
echo "  Suna 升级"
echo "======================================${NC}"
echo ""

cd "$INSTALL_DIR"

# 检查是否有更新
log "检查更新..."
git fetch origin main 2>/dev/null || {
    error "无法获取更新，请检查网络连接"
    exit 1
}

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [[ "$LOCAL" == "$REMOTE" ]]; then
    success "已是最新版本"
    echo ""
    read -p "是否强制重新构建? [y/N]: " force_rebuild
    if [[ ! "$force_rebuild" =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo "发现新版本:"
    git log --oneline HEAD..origin/main | head -10
    echo ""
fi

# 备份
if [[ "$BACKUP_BEFORE_UPGRADE" == "true" ]]; then
    log "升级前备份..."
    ./deploy/scripts/backup.sh || warn "备份失败，继续升级..."
fi

# 拉取更新
log "拉取最新代码..."
git stash 2>/dev/null || true
git pull origin main
git stash pop 2>/dev/null || true
success "代码更新完成"

# 重新构建
log "重新构建 Docker 镜像..."
docker compose -f "$COMPOSE_FILE" build --no-cache

# 滚动更新
log "重启服务..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# 等待服务健康
log "等待服务启动..."
sleep 10

# 健康检查
log "执行健康检查..."
if ./deploy/scripts/health-check.sh --quiet; then
    success "升级成功!"
else
    error "健康检查失败，请检查日志"
    echo ""
    echo "查看日志: suna logs"
    echo "回滚命令: git checkout HEAD~1 && docker compose -f $COMPOSE_FILE up -d --build"
    exit 1
fi

# 清理
log "清理旧镜像..."
docker image prune -f > /dev/null

echo ""
echo -e "${GREEN}${BOLD}升级完成!${NC}"
echo ""
echo "当前版本: $(git rev-parse --short HEAD)"
echo "查看服务状态: suna status"
