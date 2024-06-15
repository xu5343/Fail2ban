#!/bin/bash

clear
# 检查是否为Root用户
[ $(id -u) != "0" ] && { echo "错误: 您必须以root身份运行此脚本"; exit 1; }

# 读取SSH端口
[ -z "$(grep ^Port /etc/ssh/sshd_config)" ] && SSH_PORT=22 || SSH_PORT=$(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')

# 检查操作系统
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VER=$VERSION_ID
else
  echo "无法检测操作系统，请联系作者！"
  exit 1
fi

# 从用户读取信息
echo "欢迎使用 Fail2ban！"
echo "--------------------"
echo "这个Shell脚本可以通过 Fail2ban 和 firewalld 保护您的服务器免受SSH攻击"
echo ""

while :; do
  read -p "是否要更改SSH端口？ [y/n]: " ChangeSSHPort
  if [[ $ChangeSSHPort == 'y' || $ChangeSSHPort == 'Y' ]]; then
    while :; do
      read -p "请输入SSH端口(默认: $SSH_PORT): " InputSSHPort
      [ -z "$InputSSHPort" ] && InputSSHPort=$SSH_PORT
      if [[ $InputSSHPort -eq 22 || ($InputSSHPort -gt 1024 && $InputSSHPort -lt 65535) ]]; then
        SSH_PORT=$InputSSHPort
        break
      else
        echo "输入错误！输入范围: 22, 1025~65534"
      fi
    done
    sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    break
  elif [[ $ChangeSSHPort == 'n' || $ChangeSSHPort == 'N' ]]; then
    break
  else
    echo "输入错误！请仅输入 y 或 n！"
  fi
done

echo ""
read -p "输入最大尝试次数 [2-10]: " MaxRetry
echo ""
read -p "输入封锁IP的持续时间 [小时]: " BanTime
[ -z "$MaxRetry" ] && MaxRetry=3
[ -z "$BanTime" ] && BanTime=24
BanTime=$((BanTime * 60 * 60))

# 安装Fail2ban和firewalld
if [[ $OS == "centos" || $OS == "rhel" ]]; then
  yum -y install epel-release
  yum -y install fail2ban firewalld
elif [[ $OS == "ubuntu" || $OS == "debian" ]]; then
  apt-get -y update
  apt-get -y install fail2ban firewalld
else
  echo "不支持此操作系统，请联系作者！"
  exit 1
fi

# 检查并安装firewalld
if ! command -v firewall-cmd &> /dev/null; then
  echo "安装 firewalld..."
  if [[ $OS == "centos" || $OS == "rhel" ]]; then
    yum -y install firewalld
  elif [[ $OS == "ubuntu" || $OS == "debian" ]]; then
    apt-get -y install firewalld
  fi
  systemctl start firewalld
  systemctl enable firewalld
fi

# 检查安装的 Fail2ban 版本
fail2ban_version=$(fail2ban-server --version | grep -oP '\d+\.\d+\.\d+')
echo "安装的 Fail2ban 版本为: $fail2ban_version"

# 加入 firewall 默认端口
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=$SSH_PORT/tcp
firewall-cmd --reload
firewall-cmd --list-all

# 配置Fail2ban
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = $BanTime
maxretry = $MaxRetry
findtime = 1800
banaction = firewallcmd-rich-rules
action = firewallcmd-rich-rules

[sshd]
enabled = true
filter = sshd
port = ssh
logpath = /var/log/secure
maxretry = $MaxRetry

[custom-sshd]
enabled = true
filter = custom-sshd
port = $SSH_PORT
logpath = /var/log/secure
maxretry = $MaxRetry
findtime = 600
bantime = $BanTime
action = firewallcmd-rich-rules

[http-get-dos]
enabled = true
port = http,https
filter = http-get-dos
logpath = /opt/ats/var/log/node/cdnnode.log
maxretry = 800
findtime = 60
bantime = $BanTime
action = firewallcmd-rich-rules[name=HTTP, port="http,https", protocol=tcp]
EOF

# 创建自定义过滤规则文件
cat <<EOF > /etc/fail2ban/filter.d/custom-sshd.conf
[Definition]
failregex = ^.*sshd\[.*\]: Bad protocol version identification.*from <HOST> port.*
            ^.*sshd\[.*\]: Connection closed by <HOST> port.*\[preauth\]
            ^.*sshd\[.*\]: Accepted password for root from <HOST> port.*
            ^.*sshd\[.*\]: Failed password for .* from <HOST> port.*
            ^.*sshd\[.*\]: Invalid user .* from <HOST> port.*
            ^.*sshd\[.*\]: Failed \S+ for invalid user .* from <HOST> port.*
            ^.*sshd\[.*\]: User .* from <HOST> not allowed because not listed in AllowUsers$
            ^.*sshd\[.*\]: Received disconnect from <HOST>: 11: \[preauth\]$
            ^.*sshd\[.*\]: reverse mapping checking getaddrinfo for .* \[<HOST>\] failed - POSSIBLE BREAK-IN ATTEMPT!$
EOF

# 启动并设置Fail2ban为开机自启动
systemctl restart fail2ban
systemctl enable fail2ban

# 检查 Fail2ban 是否正常工作
if systemctl is-active --quiet fail2ban; then
  echo "Fail2ban 正常运行！"
else
  echo "Fail2ban 启动失败，请检查配置！"
  exit 1
fi

# 重启 SSH 服务
echo "现在重启sshd！"
systemctl restart sshd

# 检查 Fail2ban状态 是否正常
echo "Fail2ban状态"
fail2ban-client status

echo "Fail2ban sshd状态"
fail2ban-client status sshd

echo "Fail2ban http-get-dos状态"
fail2ban-client status http-get-dos

echo "Fail2ban custom-sshd状态"
fail2ban-client status custom-sshd

echo ""
echo 'Github: https://github.com/xu5343'
echo "Fail2ban 现在正在您的服务器上运行！"
