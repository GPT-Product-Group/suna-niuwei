#!/bin/bash

#===============================================================================
# Suna 健康检查脚本
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
COMPOSE_FILE="docker-compose.prod.yaml"

# 检查结果
ERRORS=0
WARNINGS=0

print_header() {
    echo ""
    echo -e "${BLUE}${BOLD}======================================"
    echo "  Suna 健康检查"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "======================================${NC}"
    echo ""
}

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((ERRORS++))
}

check_warn() {
    echo -e "  ${YELLOW}!${NC} $1"
    ((WARNINGS++))
}

check_docker() {
    echo -e "${BOLD}Docker 状态:${NC}"

    if systemctl is-active --quiet docker; then
        check_pass "Docker 服务运行中"
    else
        check_fail "Docker 服务未运行"
        return
    fi

    # 检查 Docker 版本
    local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
    check_pass "Docker 版本: $docker_version"
}

check_containers() {
    echo ""
    echo -e "${BOLD}容器状态:${NC}"

    cd "$INSTALL_DIR" 2>/dev/null || {
        check_fail "无法访问安装目录: $INSTALL_DIR"
        return
    }

    # 检查各容器
    local containers=("suna-redis" "suna-backend" "suna-worker" "suna-frontend")

    for container in "${containers[@]}"; do
        local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not found")
        local health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

        case $status in
            "running")
                if [[ "$health" == "healthy" ]]; then
                    check_pass "$container: 运行中 (健康)"
                elif [[ "$health" == "unhealthy" ]]; then
                    check_fail "$container: 运行中 (不健康)"
                else
                    check_pass "$container: 运行中"
                fi
                ;;
            "not found")
                check_fail "$container: 容器不存在"
                ;;
            *)
                check_fail "$container: $status"
                ;;
        esac
    done
}

check_services() {
    echo ""
    echo -e "${BOLD}服务健康检查:${NC}"

    # 检查 Backend API
    echo -n "  检查 Backend API... "
    local api_response=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/v1/health 2>/dev/null || echo "000")
    if [[ "$api_response" == "200" ]]; then
        echo -e "${GREEN}✓${NC} HTTP $api_response"
    else
        echo -e "${RED}✗${NC} HTTP $api_response"
        ((ERRORS++))
    fi

    # 检查 Frontend
    echo -n "  检查 Frontend... "
    local frontend_response=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000 2>/dev/null || echo "000")
    if [[ "$frontend_response" == "200" ]]; then
        echo -e "${GREEN}✓${NC} HTTP $frontend_response"
    else
        echo -e "${RED}✗${NC} HTTP $frontend_response"
        ((ERRORS++))
    fi

    # 检查 Redis
    echo -n "  检查 Redis... "
    local redis_ping=$(docker exec suna-redis redis-cli ping 2>/dev/null || echo "FAIL")
    if [[ "$redis_ping" == "PONG" ]]; then
        echo -e "${GREEN}✓${NC} PONG"
    else
        echo -e "${RED}✗${NC} $redis_ping"
        ((ERRORS++))
    fi
}

check_resources() {
    echo ""
    echo -e "${BOLD}系统资源:${NC}"

    # CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        check_warn "CPU 使用率: ${cpu_usage}%"
    else
        check_pass "CPU 使用率: ${cpu_usage}%"
    fi

    # 内存
    local mem_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    local mem_percent=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [[ $mem_percent -gt 85 ]]; then
        check_warn "内存使用: $mem_info (${mem_percent}%)"
    else
        check_pass "内存使用: $mem_info (${mem_percent}%)"
    fi

    # 磁盘
    local disk_info=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    if [[ $disk_percent -gt 85 ]]; then
        check_warn "磁盘使用: $disk_info"
    else
        check_pass "磁盘使用: $disk_info"
    fi

    # Docker 磁盘使用
    local docker_disk=$(docker system df --format "table {{.Type}}\t{{.Size}}" 2>/dev/null | tail -n +2 | head -3)
    echo "  Docker 存储:"
    echo "$docker_disk" | while read line; do
        echo "    $line"
    done
}

check_redis_stats() {
    echo ""
    echo -e "${BOLD}Redis 统计:${NC}"

    local redis_info=$(docker exec suna-redis redis-cli INFO 2>/dev/null)
    if [[ -n "$redis_info" ]]; then
        local used_memory=$(echo "$redis_info" | grep "used_memory_human:" | cut -d':' -f2 | tr -d '\r')
        local connected_clients=$(echo "$redis_info" | grep "connected_clients:" | cut -d':' -f2 | tr -d '\r')
        local keys=$(docker exec suna-redis redis-cli DBSIZE 2>/dev/null | awk '{print $2}')

        check_pass "内存使用: $used_memory"
        check_pass "连接客户端: $connected_clients"
        check_pass "键数量: $keys"
    else
        check_fail "无法获取 Redis 信息"
    fi
}

check_logs_errors() {
    echo ""
    echo -e "${BOLD}最近错误 (最近 100 行日志):${NC}"

    cd "$INSTALL_DIR" 2>/dev/null || return

    local backend_errors=$(docker logs suna-backend --tail 100 2>&1 | grep -ci "error\|exception\|traceback" || echo "0")
    local worker_errors=$(docker logs suna-worker --tail 100 2>&1 | grep -ci "error\|exception\|traceback" || echo "0")

    if [[ $backend_errors -gt 0 ]]; then
        check_warn "Backend: $backend_errors 个错误"
    else
        check_pass "Backend: 无错误"
    fi

    if [[ $worker_errors -gt 0 ]]; then
        check_warn "Worker: $worker_errors 个错误"
    else
        check_pass "Worker: 无错误"
    fi
}

check_external_connectivity() {
    echo ""
    echo -e "${BOLD}外部服务连通性:${NC}"

    # 检查 Supabase (从容器内部)
    echo -n "  检查 Supabase 连接... "
    local supabase_check=$(docker exec suna-backend curl -s -o /dev/null -w "%{http_code}" "${SUPABASE_URL:-https://supabase.co}" 2>/dev/null || echo "000")
    if [[ "$supabase_check" =~ ^[23] ]]; then
        echo -e "${GREEN}✓${NC} 可达"
    else
        echo -e "${YELLOW}!${NC} 可能不可达 (HTTP $supabase_check)"
        ((WARNINGS++))
    fi

    # 检查 Internet
    echo -n "  检查 Internet 连接... "
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        echo -e "${GREEN}✓${NC} 正常"
    else
        echo -e "${RED}✗${NC} 无法连接"
        ((ERRORS++))
    fi
}

print_summary() {
    echo ""
    echo -e "${BOLD}======================================"
    echo "  检查总结"
    echo "======================================${NC}"

    if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}所有检查通过!${NC}"
    else
        if [[ $ERRORS -gt 0 ]]; then
            echo -e "  ${RED}错误: $ERRORS${NC}"
        fi
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "  ${YELLOW}警告: $WARNINGS${NC}"
        fi
    fi

    echo ""

    # 返回状态码
    if [[ $ERRORS -gt 0 ]]; then
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# 主函数
main() {
    print_header

    check_docker
    check_containers
    check_services
    check_resources
    check_redis_stats
    check_logs_errors
    check_external_connectivity

    print_summary
}

# 解析参数
case "${1:-}" in
    --json)
        # JSON 输出模式 (用于监控系统)
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"backend_healthy\": $(curl -s http://127.0.0.1:8000/v1/health >/dev/null && echo "true" || echo "false"),"
        echo "  \"frontend_healthy\": $(curl -s http://127.0.0.1:3000 >/dev/null && echo "true" || echo "false"),"
        echo "  \"redis_healthy\": $(docker exec suna-redis redis-cli ping >/dev/null 2>&1 && echo "true" || echo "false")"
        echo "}"
        ;;
    --quiet|-q)
        # 静默模式
        exec &>/dev/null
        main
        ;;
    --help|-h)
        echo "Suna 健康检查脚本"
        echo ""
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --json     JSON 格式输出"
        echo "  --quiet    静默模式 (仅返回状态码)"
        echo "  --help     显示帮助"
        echo ""
        echo "返回码:"
        echo "  0 - 所有检查通过"
        echo "  1 - 存在错误"
        echo "  2 - 存在警告"
        ;;
    *)
        main
        ;;
esac
