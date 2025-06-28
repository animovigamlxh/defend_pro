#!/bin/bash

# 🛡️ 机场节点最终安全脚本 v6 (白名单模式)
# Airport Node Final Security Shield v6 - Whitelist Mode

echo "✅ RUNNING SCRIPT VERSION 6 (FINAL - Whitelist Mode)"
echo "🛡️ 启动机场节点最终安全防护部署 (白名单模式)..."
echo "策略：默认阻止所有出站连接，仅放行指定的核心流量 (DNS, HTTP/S)。"
echo "════════════════════════════════════════════════════════════════════"

# --- 配置区 (白名单定义) ---
ALLOWED_TCP_PORTS="5555,53,80,443"
ALLOWED_UDP_PORTS="53"
# BLOCKED_PORTS 列表已移除，因为白名单模式不再需要它。

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
    FW_TYPE="IPv$( if [ "$fw" = "iptables" ]; then echo "4"; else echo "6"; fi )"
    echo "⚙️  正在为 $fw ($FW_TYPE) 重建规则..."

    # 1. 强制清空 (Flush) OUTPUT 链中的所有旧规则
    echo "  [🧹] 正在清空 $fw 的 OUTPUT 链..."
    $fw -F OUTPUT
    
    # 2. 临时将默认策略设为 ACCEPT，以防在规则应用期间中断连接
    $fw -P OUTPUT ACCEPT

    # 3. 允许本地回环接口 (lo)
    $fw -A OUTPUT -o lo -j ACCEPT
    echo "  [✅] ($FW_TYPE) 允许本地回环 (lo) 流量"

    # 4. 允许已建立和相关的连接 (保护当前SSH会话)
    $fw -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    echo "  [✅] ($FW_TYPE) 允许已建立的连接"

    # 5. 允许核心出站流量 (DNS, HTTP/S)
    $fw -A OUTPUT -p tcp -m multiport --dports "$ALLOWED_TCP_PORTS" -j ACCEPT
    $fw -A OUTPUT -p udp -m multiport --dports "$ALLOWED_UDP_PORTS" -j ACCEPT
    echo "  [✅] ($FW_TYPE) 允许核心出站 TCP/UDP 端口"

    # 6. 允许ICMP (Ping)
    if [ "$fw" = "iptables" ]; then
        $fw -A OUTPUT -p icmp -j ACCEPT
    else
        $fw -A OUTPUT -p icmpv6 -j ACCEPT
    fi
    echo "  [✅] ($FW_TYPE) 允许 ICMP 流量"
    
    # 7. 锁定策略：将默认策略设置为 DROP (白名单模式)
    # 这是最关键的一步，所有未被明确允许的流量都将被丢弃。
    $fw -P OUTPUT DROP
    echo "  [🔒] ($FW_TYPE) 默认出站策略已设置为 DROP，白名单模式激活！"
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

echo "🎉 部署完成！您的机场节点已获得一个干净且高度安全的"白名单"防火墙。"
echo "════════════════════════════════════════════════════════════════════"
echo "📜 当前 IPv4 出站规则摘要 (策略应为 DROP):"
iptables -L OUTPUT -n --line-numbers
echo ""
echo "📜 当前 IPv6 出站规则摘要 (策略应为 DROP):"
ip6tables -L OUTPUT -n --line-numbers
echo ""
echo "✅ 这是最终的、最安全的版本。祝您使用愉快！" 
