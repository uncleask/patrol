#!/bin/bash

# =============================================================================
# Patrol Solo 环境演示脚本
# =============================================================================
# 说明：本脚本适用于 Linux 云端环境，在本地执行巡检，无需联网或免密配置
# 适用场景：快速体验 Patrol 巡检功能，单主机本地检查
# 执行方式：bash test_solo_run.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  Patrol Solo 环境演示"
echo "=========================================="
echo ""
echo "环境要求：Linux 主机（云端或本地均可）"
echo "执行方式：本地执行，无需联网或 SSH 免密"
echo ""
echo "使用的配置文件："
echo "  - servers_solo.conf   (服务器配置)"
echo "  - checks_solo.conf    (检查项配置)"
echo "  - check_groups_solo.conf (检查分组配置)"
echo ""
echo "开始执行巡检..."
echo ""

cd "$SCRIPT_DIR"

# 执行巡检
./patrol.sh \
    --servers=servers_solo.conf \
    --checks=checks_solo.conf \
    --groups=check_groups_solo.conf

echo ""
echo "=========================================="
echo "  巡检完成！"
echo "=========================================="
echo ""
echo "报告文件已生成，请查看 web/data/ 目录"
echo ""
echo "如需启动 Web 服务查看报告，请执行以下命令："
echo ""
echo "  cd web && python3 -m http.server 8000"
echo ""
echo "然后在浏览器中访问："
echo "  http://localhost:8000/index.html"
echo ""
