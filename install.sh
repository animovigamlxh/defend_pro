#!/bin/bash

# 🛡️ 机场节点最终安全脚本 v5 (强制清理版)
# Airport Node Final Security Shield v5

echo "✅ RUNNING SCRIPT VERSION 5 (FINAL)"
echo "🛡️ 启动机场节点最终安全防护部署..."
echo "策略：强制清空所有旧的出站规则，然后重建一个干净、安全的防火墙"
echo "════════════════════════════════════════════════════════════════════"

# --- 配置区 (使用最稳健的单行数组定义) ---
ALLOWED_TCP_PORTS="53,80,443"
ALLOWED_UDP_PORTS="53"
BLOCKED_PORTS=(21 22 23 25 110 135 137 138 139 143 445 465 587 993 995 1433 2022 2222 3306 3389 5432 5900 6379 27017)

# --- 脚本核心 ---

# 检查root权限
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：此脚本需要root权限运行。请使用 sudo bash $0"
  exit 1
fi

FW_COMMANDS=("iptables" "ip6tables")

# 备份当前规则，仅供紧急手动恢复
BACKUP_FILE_V4="/tmp/iptables_backup_final_$(date +%Y%m%d_%H%M%S).v4.rules"
BACKUP_FILE_V6="/tmp/ip6tables_backup_final_$(date +%Y%m%d_%H%M%S).v6.rules"
echo "🔄 正在备份当前规则 (仅供紧急手动恢复)..."
iptables-save > "$BACKUP_FILE_V4"
ip6tables-save > "$BACKUP_FILE_V6"
echo "✅ 备份完成。"

for fw in "${FW_COMMANDS[@]}"; do
    FW_TYPE="IPv${fw:2:1}"
    echo "⚙️  正在为 $fw ($FW_TYPE) 重建规则..."

    # 1. 强制清空 (Flush) OUTPUT 链中的所有旧规则
    echo "  [🧹] 正在清空 $fw 的 OUTPUT 链..."
    $fw -F OUTPUT

    # 2. 允许本地回环接口 (lo)
    $fw -A OUTPUT -o lo -j ACCEPT
    echo "  [✅] ($FW_TYPE) 允许本地回环 (lo) 流量"

    # 3. 允许已建立和相关的连接 (保护当前SSH会话)
    $fw -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo "  [✅] ($FW_TYPE) 允许已建立的连接"

    # 4. 允许核心出站流量 (DNS, HTTP/S)
    $fw -A OUTPUT -p tcp -m multiport --dports "$ALLOWED_TCP_PORTS" -j ACCEPT
    $fw -A OUTPUT -p udp -m multiport --dports "$ALLOWED_UDP_PORTS" -j ACCEPT
    echo "  [✅] ($FW_TYPE) 允许核心出站 TCP/UDP 端口"

    # 5. 允许ICMP (Ping)
    if [ "$fw" = "iptables" ]; then
        $fw -A OUTPUT -p icmp -j ACCEPT
    else
        $fw -A OUTPUT -p icmpv6 -j ACCEPT
    fi
    echo "  [✅] ($FW_TYPE) 允许 ICMP 流量"
    
    # 6. 阻止所有明确定义的高危端口
    log_prefix="ABUSE_BLOCKED_${FW_TYPE}: "
    echo "  [🚫] ($FW_TYPE) 正在逐一阻止高危端口..."
    for port in "${BLOCKED_PORTS[@]}"; do
        $fw -A OUTPUT -p tcp --dport "$port" -j LOG --log-prefix "$log_prefix"
        $fw -A OUTPUT -p tcp --dport "$port" -j DROP
        $fw -A OUTPUT -p udp --dport "$port" -j LOG --log-prefix "$log_prefix"
        $fw -A OUTPUT -p udp --dport "$port" -j DROP
    done
    echo "  [👍] ($FW_TYPE) 高危端口已全部阻止"
done


# --- 保存规则以实现持久化 ---
echo "💾 正在永久保存防火墙规则..."
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
else
    if command -v apt-get &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent || true
    fi
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
fi

echo "🎉 部署完成！您的机场节点已获得一个干净且受保护的防火墙。"
echo "════════════════════════════════════════════════════════════════════"
echo "📜 当前 IPv4 出站规则摘要 (应该非常干净):"
iptables -L OUTPUT -n --line-numbers
echo ""
echo "📜 当前 IPv6 出站规则摘要 (应该非常干净):"
ip6tables -L OUTPUT -n --line-numbers
echo ""
echo "✅ 这是最终的、最可靠的版本。祝您使用愉快！" 
