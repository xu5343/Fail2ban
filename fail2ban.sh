#!/bin/bash

clear
# 检查是否为Root用户
[ $(id -u) != "0" ] && { echo "错误: 您必须以root身份运行此脚本"; exit 1; }

# 读取SSH端口
[ -z "$(grep ^Port /etc/ssh/sshd_config)" ] && ssh_port=22 || ssh_port=$(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')

# 检查操作系统
if [ -n "$(grep 'Aliyun Linux release' /etc/issue)" -o -e /etc/redhat-release ]; then
  OS=CentOS
  [ -n "$(grep ' 7\.' /etc/redhat-release)" ] && CentOS_RHEL_version=7
  [ -n "$(grep ' 6\.' /etc/redhat-release)" -o -n "$(grep 'Aliyun Linux release6 15' /etc/issue)" ] && CentOS_RHEL_version=6
  [ -n "$(grep ' 5\.' /etc/redhat-release)" -o -n "$(grep 'Aliyun Linux release5' /etc/issue)" ] && CentOS_RHEL_version=5
elif [ -n "$(grep 'Amazon Linux AMI release' /etc/issue)" -o -e /etc/system-release ]; then
  OS=CentOS
  CentOS_RHEL_version=6
elif [ -n "$(grep 'bian' /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == "Debian" ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Debian_version=$(lsb_release -sr | awk -F. '{print $1}')
elif [ -n "$(grep 'Deepin' /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == "Deepin" ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Debian_version=$(lsb_release -sr | awk -F. '{print $1}')
elif [ -n "$(grep 'Kali GNU/Linux Rolling' /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == "Kali" ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  if [ -n "$(grep 'VERSION=\"2016.*\"' /etc/os-release)" ]; then
    Debian_version=8
  else
    echo "不支持此操作系统，请联系作者！"
    kill -9 $$
  fi
elif [ -n "$(grep 'Ubuntu' /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == "Ubuntu" -o -n "$(grep 'Linux Mint' /etc/issue)" ]; then
  OS=Ubuntu
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Ubuntu_version=$(lsb_release -sr | awk -F. '{print $1}')
  [ -n "$(grep 'Linux Mint 18' /etc/issue)" ] && Ubuntu_version=16
elif [ -n "$(grep 'elementary' /etc/issue)" -o "$(lsb_release -is 2>/dev/null)" == 'elementary' ]; then
  OS=Ubuntu
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Ubuntu_version=16
else
  echo "不支持此操作系统，请联系作者！"
  kill -9 $$
fi

# 从用户读取信息
echo "欢迎使用 Fail2ban！"
echo "--------------------"
echo "这个Shell脚本可以通过 Fail2ban 和 iptables 保护您的服务器免受SSH攻击"
echo ""

while :; do echo
  read -p "是否要更改SSH端口？ [y/n]: " IfChangeSSHPort
  if [ ${IfChangeSSHPort} == 'y' ]; then
    if [ -e "/etc/ssh/sshd_config" ];then
      [ -z "$(grep ^Port /etc/ssh/sshd_config)" ] && ssh_port=22 || ssh_port=$(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')
      while :; do echo
        read -p "请输入SSH端口(默认: $ssh_port): " SSH_PORT
        [ -z "$SSH_PORT" ] && SSH_PORT=$ssh_port
        if [[ $SSH_PORT -eq 22 ]] || [[ $SSH_PORT -gt 1024 && $SSH_PORT -lt 65535 ]]; then
          break
        else
          echo "输入错误！输入范围: 22, 1025~65534"
        fi
      done
      if [ -z "$(grep ^Port /etc/ssh/sshd_config)" -a "$SSH_PORT" != '22' ]; then
        echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
      elif [ -n "$(grep ^Port /etc/ssh/sshd_config)" ]; then
        sed -i "s@^Port.*@Port $SSH_PORT@" /etc/ssh/sshd_config
      fi
    fi
    break
  elif [ ${IfChangeSSHPort} == 'n' ]; then
    SSH_PORT=$ssh_port
    break
  else
    echo "输入错误！请仅输入 y 或 n！"
  fi
done
ssh_port=$SSH_PORT
echo ""
read -p "输入最大尝试次数 [2-10]: " maxretry
echo ""
read -p "输入封锁IP的持续时间 [小时]: " bantime
[ -z ${maxretry} ] && maxretry=3
[ -z ${bantime} ] && bantime=24
((bantime=$bantime*60*60))

# 安装Fail2ban
if [ ${OS} == CentOS ]; then
  yum -y install epel-release
  yum -y install fail2ban
elif [[ ${OS} =~ ^Ubuntu$|^Debian$ ]]; then
  apt-get -y update
  apt-get -y install fail2ban
fi

# 检查安装的 Fail2ban 版本
fail2ban_version=$(fail2ban-server --version | grep -oP '\d+\.\d+\.\d+')
echo "安装的 Fail2ban 版本为: $fail2ban_version"

# 配置Fail2ban
rm -rf /etc/fail2ban/jail.local
touch /etc/fail2ban/jail.local
if [ ${OS} == CentOS ]; then
  cat <<EOF >> /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1
bantime = 86400
maxretry = $maxretry
findtime = 1800

[ssh-iptables]
enabled = true
filter = sshd
action = iptables[name=SSH, port=ssh, protocol=tcp]
logpath = /var/log/secure
maxretry = $maxretry
findtime = 3600
bantime = $bantime

[cc-attack]
enabled = true
filter = cc-attack
action = iptables[name=CC-ATTACK-HTTP, port=http, protocol=tcp]
         iptables[name=CC-ATTACK-HTTPS, port=https, protocol=tcp]
logpath = /var/log/apache2/access.log
          /var/log/nginx/access.log
maxretry = 200
findtime = 600
bantime = 3600

[custom-sshd]
enabled = true
filter = custom-sshd
port = $ssh_port
logpath = /var/log/secure
maxretry = $maxretry
findtime = 600
bantime = $bantime
action = %(action_mwl)s
EOF
else
  cat <<EOF >> /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1
bantime = 86400
maxretry = $maxretry
findtime = 1800

[ssh-iptables]
enabled = true
filter = sshd
action = iptables[name=SSH, port=ssh, protocol=tcp]
logpath = /var/log/auth.log
maxretry = $maxretry
findtime = 3600
bantime = $bantime

[cc-attack]
enabled = true
filter = cc-attack
action = iptables[name=CC-ATTACK-HTTP, port=http, protocol=tcp]
         iptables[name=CC-ATTACK-HTTPS, port=https, protocol=tcp]
logpath = /var/log/apache2/access.log
          /var/log/nginx/access.log
maxretry = 200
findtime = 600
bantime = 3600

[custom-sshd]
enabled = true
filter = custom-sshd
port = $ssh_port
logpath = /var/log/auth.log
maxretry = $maxretry
findtime = 3600
bantime = $bantime
action = %(action_mwl)s
EOF
fi

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

# 创建自定义过滤规则文件
cat <<EOF > /etc/fail2ban/filter.d/cc-attack.conf
[Definition]
failregex = ^<HOST> -.*"(GET|POST).*
ignoreregex =
EOF

# 启动并设置Fail2ban为开机自启动
if [ ${OS} == CentOS ]; then
  if [ ${CentOS_RHEL_version} == 7 ]; then
    systemctl restart fail2ban
    systemctl enable fail2ban
  else
    service fail2ban restart
    chkconfig fail2ban on
  fi
elif [[ ${OS} =~ ^Ubuntu$|^Debian$ ]]; then
  systemctl restart fail2ban
  systemctl enable fail2ban
fi

# 检查 Fail2ban 是否正常工作
fail2ban_status=$(systemctl is-active fail2ban)
if [ $fail2ban_status == "active" ]; then
  echo "Fail2ban 正常运行！"
else
  echo "Fail2ban 启动失败，请检查配置！"
fi

# 重启 SSH 服务
echo "现在重启sshd！"
if [ ${OS} == CentOS ]; then
  if [ ${CentOS_RHEL_version} == 7 ]; then
    systemctl restart sshd
  else
    service ssh restart
  fi
elif [[ ${OS} =~ ^Ubuntu$|^Debian$ ]]; then
  service ssh restart
fi

# 检查 Fail2ban状态 是否正常
echo "Fail2ban状态"
fail2ban-client status

echo "Fail2ban ssh-iptables状态"
fail2ban-client status ssh-iptables

echo "Fail2ban custom-sshd状态"
fail2ban-client status custom-sshd

echo ""
echo 'Github: https://github.com/xu5343'
echo "Fail2ban 现在正在您的服务器上运行！"
