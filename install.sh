#!/bin/bash

# 🛡️ 机场节点双栈安全防护脚本 (IPv4 & IPv6) - v4 (最终修复版)
# 策略：强制清空旧规则，然后重新构建一个干净、安全的防火墙

echo "🛡️ 启动机场节点双栈安全防护部署 (v4)..."
echo "策略：强制清空旧规则，然后重新构建防火墙"
echo "════════════════════════════════════════════════════════════════════"

# --- 配置区 ---
ALLOWED_TCP_PORTS="53,80,443"
ALLOWED_UDP_PORTS="53"
BLOCKED_PORTS=(
    21 22 23 25 110 135 137 138 139 143 445 465 587 993 995
    1433 2022 2222 3306 3389 5432 5900 6379 27017
)

# --- 脚本核心 ---

# 检查root权限
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：此脚本需要root权限运行。请使用 sudo bash $0"
  exit 1
fi

FW_COMMANDS=("iptables" "ip6tables")

# 备份当前防火墙规则 (仅用于手动恢复，脚本不再依赖它)
BACKUP_FILE_V4="/tmp/iptables_backup_$(date +%Y%m%d_%H%M%S).v4.rules"
BACKUP_FILE_V6="/tmp/ip6tables_backup_$(date +%Y%m%d_%H%M%S).v6.rules"
echo "🔄 正在备份当前防火墙规则..."
iptables-save > "$BACKUP_FILE_V4"
ip6tables-save > "$BACKUP_FILE_V6"
echo "✅ 备份完成。备份文件仅供紧急手动恢复使用。"

for fw in "${FW_COMMANDS[@]}"; do
    echo "⚙️  正在为 $fw (IPv${fw:2:1}) 重建规则..."

    # 1. 强制清空 (Flush) OUTPUT 链中的所有旧规则
    echo "  [🧹] 正在清空 $fw 的 OUTPUT 链..."
    $fw -F OUTPUT

    # 2. 允许本地回环接口 (非常重要)
    $fw -A OUTPUT -o lo -j ACCEPT
    echo "  [✅] 允许本地回环 (lo) 流量"

    # 3. 允许已建立的和相关的连接 (非常重要，否则你的SSH会断开)
    $fw -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo "  [✅] 允许已建立的连接"

    # 4. 允许核心出站流量 (DNS, HTTP/S)
    $fw -A OUTPUT -p tcp -m multiport --dports "$ALLOWED_TCP_PORTS" -j ACCEPT
    $fw -A OUTPUT -p udp -m multiport --dports "$ALLOWED_UDP_PORTS" -j ACCEPT
    echo "  [✅] 允许核心 TCP/UDP 端口"

    # 5. 允许ICMP (Ping)
    if [ "$fw" = "iptables" ]; then
        $fw -A OUTPUT -p icmp -j ACCEPT
    else
        $fw -A OUTPUT -p icmpv6 -j ACCEPT
    fi
    echo "  [✅] 允许 ICMP 流量"
    
    # 6. 阻止所有明确定义的高危端口
    log_prefix="ABUSE_BLOCKED_${fw:2:1}: "
    echo "  [🚫] 正在阻止高危端口出站..."
    for port in "${BLOCKED_PORTS[@]}"; do
        $fw -A OUTPUT -p tcp --dport "$port" -j LOG --log-prefix "$log_prefix"
        $fw -A OUTPUT -p tcp --dport "$port" -j DROP
        $fw -A OUTPUT -p udp --dport "$port" -j LOG --log-prefix "$log_prefix"
        $fw -A OUTPUT -p udp --dport "$port" -j DROP
    done
    echo "  [👍] 高危端口阻止规则部署完成"
done


# --- 保存规则以实现持久化 ---
echo "💾 正在永久保存防火墙规则..."
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
else
    # 对于没有netfilter-persistent的系统，提供备用方案
    if command -v apt-get &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent || echo "请手动安装 iptables-persistent"
    elif command -v yum &> /dev/null; then
        yum install -y iptables-services && systemctl enable iptables && systemctl enable ip6tables
    fi
    # 保存规则
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
    service iptables save 2>/dev/null
    service ip6tables save 2>/dev/null
fi

echo "🎉 部署完成！您的机场节点已获得一个干净且受保护的防火墙。"
echo "════════════════════════════════════════════════════════════════════"
echo "📜 请检查下面的规则列表，它现在应该非常干净整洁。"
echo "📜 当前 IPv4 出站规则摘要:"
iptables -L OUTPUT -n --line-numbers
echo ""
echo "📜 当前 IPv6 出站规则摘要:"
ip6tables -L OUTPUT -n --line-numbers
echo ""
echo "🔧 管理命令:"
echo "  - 查看被阻止的日志: sudo dmesg | grep 'ABUSE_BLOCKED'"
echo "  - 恢复到运行前 (IPv4): sudo iptables-restore < $BACKUP_FILE_V4"
echo "  - 恢复到运行前 (IPv6): sudo ip6tables-restore < $BACKUP_FILE_V6"
echo ""
echo "✅ 这是最终的、最可靠的版本。祝您使用愉快！" 
