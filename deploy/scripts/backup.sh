#!/bin/bash

#===============================================================================
# Suna 备份脚本
#===============================================================================

set -e

# 配置
INSTALL_DIR="${SUNA_INSTALL_DIR:-/opt/suna}"
BACKUP_DIR="${BACKUP_DIR:-$INSTALL_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DATE=$(date +%Y%m%d_%H%M%S)

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

# 创建备份目录
mkdir -p "$BACKUP_DIR/redis"
mkdir -p "$BACKUP_DIR/config"
mkdir -p "$BACKUP_DIR/logs"

echo ""
echo "======================================"
echo "  Suna 备份 - $DATE"
echo "======================================"
echo ""

# 1. 备份 Redis
log "备份 Redis 数据..."
docker exec suna-redis redis-cli BGSAVE > /dev/null 2>&1
sleep 3
docker cp suna-redis:/data/dump.rdb "$BACKUP_DIR/redis/redis_$DATE.rdb"
gzip -f "$BACKUP_DIR/redis/redis_$DATE.rdb"
success "Redis 备份完成: redis_$DATE.rdb.gz"

# 2. 备份配置文件
log "备份配置文件..."
tar -czf "$BACKUP_DIR/config/config_$DATE.tar.gz" \
    -C "$INSTALL_DIR" \
    backend/.env \
    frontend/.env \
    docker-compose.prod.yaml \
    2>/dev/null || true
success "配置备份完成: config_$DATE.tar.gz"

# 3. 备份日志 (可选)
if [[ "${BACKUP_LOGS:-false}" == "true" ]]; then
    log "备份日志..."
    docker logs suna-backend > "$BACKUP_DIR/logs/backend_$DATE.log" 2>&1
    docker logs suna-worker > "$BACKUP_DIR/logs/worker_$DATE.log" 2>&1
    docker logs suna-frontend > "$BACKUP_DIR/logs/frontend_$DATE.log" 2>&1
    gzip -f "$BACKUP_DIR/logs/"*_$DATE.log
    success "日志备份完成"
fi

# 4. 清理旧备份
log "清理 $RETENTION_DAYS 天前的备份..."
find "$BACKUP_DIR" -name "*.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
success "旧备份已清理"

# 5. 显示备份统计
echo ""
echo "======================================"
echo "  备份统计"
echo "======================================"
echo ""
echo "备份目录: $BACKUP_DIR"
echo ""
echo "Redis 备份:"
ls -lh "$BACKUP_DIR/redis/"*.gz 2>/dev/null | tail -5 || echo "  无"
echo ""
echo "配置备份:"
ls -lh "$BACKUP_DIR/config/"*.tar.gz 2>/dev/null | tail -5 || echo "  无"
echo ""
echo "总大小: $(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')"
echo ""

success "备份完成!"
