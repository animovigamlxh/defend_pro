#!/bin/bash

# 🛡️ 机场节点出站攻击防护脚本 (Airport Node Security Shield)
# 策略：默认允许常用网络流量，精准阻止高危端口的出站连接。

echo "🛡️ 启动机场节点安全防护部署..."
echo "策略：允许常用流量 (DNS, HTTP/S)，阻止高危端口 (SSH, SMTP, DBs) 的出站攻击"
echo "════════════════════════════════════════════════════════════════════"

# --- 配置区 ---
# 允许的出站TCP端口 (用户正常上网所需)
ALLOWED_TCP_PORTS="53,80,443"

# 允许的出站UDP端口
ALLOWED_UDP_PORTS="53"

# 需要阻止的高危出站端口列表 (防止滥用)
BLOCKED_PORTS=(
    21,22,23,25,110,135,137,138,139,143,445,465,587,993,995,
    1433,2022,2222,3306,3389,5432,5900,6379,27017
)
# 端口说明:
# 21: FTP, 22: SSH, 23: Telnet, 25/465/587: SMTP (垃圾邮件)
# 110/995: POP3, 143/993: IMAP, 135/137-139/445: SMB/RPC (Windows漏洞)
# 1433: MSSQL, 2022/2222: Alt SSH, 3306: MySQL, 3389: RDP
# 5432: PostgreSQL, 5900: VNC, 6379: Redis, 27017: MongoDB

# --- 脚本核心 ---

# 检查root权限
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：此脚本需要root权限运行。请使用 sudo bash $0"
  exit 1
fi

# 备份当前防火墙规则
BACKUP_FILE="/tmp/iptables_airport_backup_$(date +%Y%m%d_%H%M%S).rules"
echo "🔄 正在备份当前防火墙规则到 $BACKUP_FILE..."
iptables-save > "$BACKUP_FILE"
echo "✅ 备份完成。"

# 清理旧的防护规则 (如果存在的话，防止重复添加)
echo "🧹 正在清理可能存在的旧防护规则..."
for port in "${BLOCKED_PORTS[@]}"; do
    iptables -D OUTPUT -p tcp --dport "$port" -j DROP 2>/dev/null
    iptables -D OUTPUT -p udp --dport "$port" -j DROP 2>/dev/null
done

# --- 部署防火墙规则 ---
echo "⚙️  正在部署新的安全防护规则..."

# 1. 允许本地回环接口 (非常重要)
iptables -A OUTPUT -o lo -j ACCEPT
echo "  [✅] 允许本地回环 (lo) 流量"

# 2. 允许已建立的和相关的连接 (非常重要，否则你的SSH会断开)
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
echo "  [✅] 允许已建立的连接 (ESTABLISHED,RELATED)"

# 3. 允许核心出站流量
iptables -A OUTPUT -p tcp -m multiport --dports "$ALLOWED_TCP_PORTS" -j ACCEPT
echo "  [✅] 允许出站 TCP 端口: $ALLOWED_TCP_PORTS (DNS, HTTP, HTTPS)"
iptables -A OUTPUT -p udp -m multiport --dports "$ALLOWED_UDP_PORTS" -j ACCEPT
echo "  [✅] 允许出站 UDP 端口: $ALLOWED_UDP_PORTS (DNS)"

# 4. 允许ICMP (Ping)，用于网络诊断
iptables -A OUTPUT -p icmp -j ACCEPT
echo "  [✅] 允许 ICMP (Ping)"

# 5. 阻止所有明确定义的高危端口
echo "  [🚫] 正在阻止高危端口出站..."
for port in "${BLOCKED_PORTS[@]}"; do
    iptables -A OUTPUT -p tcp --dport "$port" -j LOG --log-prefix "ABUSE_BLOCKED_TCP: "
    iptables -A OUTPUT -p tcp --dport "$port" -j DROP
    iptables -A OUTPUT -p udp --dport "$port" -j LOG --log-prefix "ABUSE_BLOCKED_UDP: "
    iptables -A OUTPUT -p udp --dport "$port" -j DROP
    echo "      - 已阻止端口: $port"
done

# --- 保存规则以实现持久化 ---
echo "💾 正在永久保存防火墙规则..."
# For Debian/Ubuntu
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif command -v iptables-persistent &> /dev/null; then
    iptables-persistent save
else
    apt-get update && apt-get install -y iptables-persistent || echo "请手动安装 iptables-persistent"
    netfilter-persistent save
fi
# For CentOS/RHEL
if command -v firewall-cmd &> /dev/null; then
    echo "检测到 firewalld，建议使用firewall-cmd管理规则。此脚本主要用于iptables。"
else
    service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables 2>/dev/null
fi

echo "🎉 部署完成！您的机场节点已受基础保护。"
echo "════════════════════════════════════════════════════════════════════"
echo "📜 当前出站规则摘要:"
iptables -L OUTPUT -n --line-numbers
echo ""
echo "🔧 管理命令:"
echo "  - 查看被阻止的连接日志: dmesg | grep 'ABUSE_BLOCKED'"
echo "  - 临时允许某个端口 (例如 22): sudo iptables -I OUTPUT 5 -p tcp --dport 22 -j ACCEPT"
echo "  - 恢复到运行脚本之前的状态: sudo iptables-restore < $BACKUP_FILE"
echo ""
echo "⚠️  重要提示：请将备份文件 '$BACKUP_FILE' 保存到安全位置！"
