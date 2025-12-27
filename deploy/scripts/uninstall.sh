#!/bin/bash

#===============================================================================
# Suna 卸载脚本
#===============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

INSTALL_DIR="${SUNA_INSTALL_DIR:-/opt/suna}"

echo -e "${RED}${BOLD}"
cat << 'EOF'
  _   _       _           _        _ _
 | | | |_ __ (_)_ __  ___| |_ __ _| | |
 | | | | '_ \| | '_ \/ __| __/ _` | | |
 | |_| | | | | | | | \__ \ || (_| | | |
  \___/|_| |_|_|_| |_|___/\__\__,_|_|_|

EOF
echo -e "${NC}"

echo -e "${YELLOW}${BOLD}警告: 此操作将卸载 Suna 及其相关组件${NC}"
echo ""
echo "将执行以下操作:"
echo "  1. 停止并删除所有 Suna Docker 容器"
echo "  2. 删除 Docker 镜像"
echo "  3. 删除 Docker 数据卷 (可选)"
echo "  4. 删除 Nginx 配置"
echo "  5. 删除 Systemd 服务"
echo "  6. 删除 suna 命令"
echo "  7. 删除安装目录 (可选)"
echo ""

read -p "确定要继续吗? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    exit 1
fi

# 停止服务
echo -e "${BLUE}[1/7]${NC} 停止 Docker 服务..."
if [[ -f "$INSTALL_DIR/docker-compose.prod.yaml" ]]; then
    cd "$INSTALL_DIR"
    docker compose -f docker-compose.prod.yaml down 2>/dev/null || true
fi

# 停止 systemd 服务
systemctl stop suna.service 2>/dev/null || true
systemctl disable suna.service 2>/dev/null || true

echo -e "${GREEN}✓${NC} 服务已停止"

# 删除容器
echo -e "${BLUE}[2/7]${NC} 删除 Docker 容器..."
docker rm -f suna-redis suna-backend suna-worker suna-frontend 2>/dev/null || true
echo -e "${GREEN}✓${NC} 容器已删除"

# 删除镜像
echo -e "${BLUE}[3/7]${NC} 删除 Docker 镜像..."
docker rmi suna-backend suna-frontend 2>/dev/null || true
echo -e "${GREEN}✓${NC} 镜像已删除"

# 数据卷
echo ""
read -p "是否删除 Docker 数据卷 (包含 Redis 数据)? [y/N]: " delete_volumes
if [[ "$delete_volumes" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[4/7]${NC} 删除 Docker 数据卷..."
    docker volume rm suna_redis_data 2>/dev/null || true
    docker volume rm $(docker volume ls -q --filter name=suna) 2>/dev/null || true
    echo -e "${GREEN}✓${NC} 数据卷已删除"
else
    echo -e "${YELLOW}!${NC} 跳过数据卷删除"
fi

# 删除 Nginx 配置
echo -e "${BLUE}[5/7]${NC} 删除 Nginx 配置..."
rm -f /etc/nginx/sites-enabled/suna
rm -f /etc/nginx/sites-available/suna
nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
echo -e "${GREEN}✓${NC} Nginx 配置已删除"

# 删除 Systemd 服务
echo -e "${BLUE}[6/7]${NC} 删除 Systemd 服务..."
rm -f /etc/systemd/system/suna.service
systemctl daemon-reload
echo -e "${GREEN}✓${NC} Systemd 服务已删除"

# 删除 suna 命令
echo -e "${BLUE}[7/7]${NC} 删除 suna 命令..."
rm -f /usr/local/bin/suna
echo -e "${GREEN}✓${NC} suna 命令已删除"

# 删除安装目录
echo ""
read -p "是否删除安装目录 $INSTALL_DIR ? [y/N]: " delete_install
if [[ "$delete_install" =~ ^[Yy]$ ]]; then
    # 备份配置文件
    if [[ -f "$INSTALL_DIR/backend/.env" ]]; then
        backup_dir="/tmp/suna-backup-$(date +%Y%m%d%H%M%S)"
        mkdir -p "$backup_dir"
        cp "$INSTALL_DIR/backend/.env" "$backup_dir/" 2>/dev/null || true
        cp "$INSTALL_DIR/frontend/.env" "$backup_dir/" 2>/dev/null || true
        echo -e "${YELLOW}配置文件已备份到: $backup_dir${NC}"
    fi

    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}✓${NC} 安装目录已删除"
else
    echo -e "${YELLOW}!${NC} 跳过安装目录删除"
fi

# 清理 Docker
echo ""
read -p "是否清理未使用的 Docker 资源? [y/N]: " cleanup_docker
if [[ "$cleanup_docker" =~ ^[Yy]$ ]]; then
    docker system prune -f
    echo -e "${GREEN}✓${NC} Docker 资源已清理"
fi

echo ""
echo -e "${GREEN}${BOLD}卸载完成!${NC}"
echo ""

# 可选: 删除 Docker
read -p "是否同时卸载 Docker? [y/N]: " remove_docker
if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
    apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    apt-get autoremove -y
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    echo -e "${GREEN}✓${NC} Docker 已卸载"
fi

echo ""
echo "如需重新安装，请运行: sudo ./deploy.sh"
