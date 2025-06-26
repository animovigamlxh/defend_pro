#!/bin/bash

# 🛡️ 机场节点双栈安全防护脚本 (IPv4 & IPv6) - v2 (修复版)
# Airport Node Dual-Stack Security Shield

echo "🛡️ 启动机场节点双栈 (IPv4 & IPv6) 安全防护部署 (v2)..."
echo "策略：允许常用流量 (DNS, HTTP/S)，阻止高危端口 (SSH, SMTP, DBs) 的出站攻击"
echo "════════════════════════════════════════════════════════════════════"

# --- 配置区 (修复端口列表格式) ---
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

# 定义防火墙命令数组，方便同时操作IPv4和IPv6
FW_COMMANDS=("iptables" "ip6tables")

# 备份当前防火墙规则
BACKUP_FILE_V4="/tmp/iptables_backup_$(date +%Y%m%d_%H%M%S).v4.rules"
BACKUP_FILE_V6="/tmp/ip6tables_backup_$(date +%Y%m%d_%H%M%S).v6.rules"
echo "🔄 正在备份当前防火墙规则..."
iptables-save > "$BACKUP_FILE_V4"
ip6tables-save > "$BACKUP_FILE_V6"
echo "✅ IPv4 规则备份到: $BACKUP_FILE_V4"
echo "✅ IPv6 规则备份到: $BACKUP_FILE_V6"

for fw in "${FW_COMMANDS[@]}"; do
    echo "⚙️  正在为 $fw (IPv${fw:2:1}) 部署规则..."

    # 清理可能存在的旧规则
    for port in "${BLOCKED_PORTS[@]}"; do
        $fw -D OUTPUT -p tcp --dport "$port" -j DROP 2>/dev/null
        $fw -D OUTPUT -p udp --dport "$port" -j DROP 2>/dev/null
    done

    # 1. 允许本地回环接口
    $fw -A OUTPUT -o lo -j ACCEPT

    # 2. 允许已建立的和相关的连接
    $fw -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # 3. 允许核心出站流量
    $fw -A OUTPUT -p tcp -m multiport --dports "$ALLOWED_TCP_PORTS" -j ACCEPT
    $fw -A OUTPUT -p udp -m multiport --dports "$ALLOWED_UDP_PORTS" -j ACCEPT

    # 4. 允许ICMP (Ping)
    if [ "$fw" = "iptables" ]; then
        $fw -A OUTPUT -p icmp -j ACCEPT # For IPv4
    else
        $fw -A OUTPUT -p icmpv6 -j ACCEPT # For IPv6
    fi
    
    # 5. 阻止所有明确定义的高危端口
    log_prefix="ABUSE_BLOCKED_${fw:2:1}: "
    for port in "${BLOCKED_PORTS[@]}"; do
        $fw -A OUTPUT -p tcp --dport "$port" -j LOG --log-prefix "$log_prefix"
        $fw -A OUTPUT -p tcp --dport "$port" -j DROP
        $fw -A OUTPUT -p udp --dport "$port" -j LOG --log-prefix "$log_prefix"
        $fw -A OUTPUT -p udp --dport "$port" -j DROP
    done
done


# --- 保存规则以实现持久化 ---
echo "💾 正在永久保存 IPv4 和 IPv6 的防火墙规则..."
# For Debian/Ubuntu
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif command -v iptables-persistent &> /dev/null; then
    # 确保 ip6tables-persistent 也安装了
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    # 它会自动处理v4和v6
    iptables-persistent save
else
    # 尝试安装
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent || echo "请手动安装 iptables-persistent 以便规则持久化"
    netfilter-persistent save
fi

# For CentOS/RHEL
if command -v firewall-cmd &> /dev/null; then
    echo "检测到 firewalld，建议使用firewall-cmd管理规则。此脚本主要用于iptables。"
else
    service iptables save 2>/dev/null
    service ip6tables save 2>/dev/null
    # 或者
    iptables-save > /etc/sysconfig/iptables 2>/dev/null
    ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null
fi

echo "🎉 部署完成！您的机场节点已受 IPv4 和 IPv6 双重保护。"
echo "════════════════════════════════════════════════════════════════════"
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
echo "⚠️  重要提示：请将备份文件 '$BACKUP_FILE_V4' 和 '$BACKUP_FILE_V6' 保存到安全位置！" 
