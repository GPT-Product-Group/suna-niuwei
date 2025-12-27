#!/bin/bash

#===============================================================================
# Suna 快速安装脚本
# 用法: curl -fsSL https://your-repo/quick-install.sh | sudo bash
#===============================================================================

set -e

REPO_URL="${SUNA_REPO:-https://github.com/GPT-Product-Group/suna-niuwei.git}"
INSTALL_DIR="${SUNA_INSTALL_DIR:-/opt/suna}"
BRANCH="${SUNA_BRANCH:-main}"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${CYAN}"
cat << 'EOF'
  ____
 / ___| _   _ _ __   __ _
 \___ \| | | | '_ \ / _` |
  ___) | |_| | | | | (_| |
 |____/ \__,_|_| |_|\__,_|

 Quick Installer
EOF
echo -e "${NC}"

# 检查 root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 root 权限运行此脚本${NC}"
    echo "使用: sudo $0"
    exit 1
fi

# 检查系统
echo -e "${BLUE}[1/4]${NC} 检查系统环境..."
if [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}不支持的操作系统${NC}"
    exit 1
fi

source /etc/os-release
echo "  操作系统: $PRETTY_NAME"
echo "  架构: $(uname -m)"

# 安装基础依赖
echo ""
echo -e "${BLUE}[2/4]${NC} 安装基础依赖..."
apt-get update -qq
apt-get install -y -qq git curl > /dev/null 2>&1
echo -e "${GREEN}✓${NC} 依赖安装完成"

# 克隆项目
echo ""
echo -e "${BLUE}[3/4]${NC} 下载 Suna..."
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}!${NC} 安装目录已存在: $INSTALL_DIR"
    read -p "是否删除并重新安装? [y/N]: " reinstall
    if [[ "$reinstall" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
    else
        echo "使用现有安装目录"
    fi
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi
echo -e "${GREEN}✓${NC} 下载完成"

# 运行部署脚本
echo ""
echo -e "${BLUE}[4/4]${NC} 运行部署脚本..."
chmod +x "$INSTALL_DIR/deploy/deploy.sh"
chmod +x "$INSTALL_DIR/deploy/scripts/"*.sh 2>/dev/null || true

echo ""
echo -e "${GREEN}${BOLD}下载完成!${NC}"
echo ""
echo "接下来请运行部署脚本:"
echo ""
echo -e "  ${CYAN}cd $INSTALL_DIR && sudo ./deploy/deploy.sh${NC}"
echo ""
echo "或者先编辑配置文件:"
echo ""
echo -e "  ${CYAN}cp $INSTALL_DIR/deploy/config.env.example $INSTALL_DIR/deploy/config.env${NC}"
echo -e "  ${CYAN}vim $INSTALL_DIR/deploy/config.env${NC}"
echo -e "  ${CYAN}cd $INSTALL_DIR && sudo ./deploy/deploy.sh --auto${NC}"
echo ""
