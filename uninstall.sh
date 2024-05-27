#!/bin/bash
clear

# Check if running as root
[ $(id -u) != "0" ] && { echo "错误: 您必须以root身份运行此脚本"; exit 1; }

# Read SSH Port
ssh_port=$(grep ^Port /etc/ssh/sshd_config | awk '{print $2}')
[ -z "$ssh_port" ] && ssh_port=22

# Determine OS
if [ -n "$(grep 'Aliyun Linux release' /etc/issue)" ] || [ -e /etc/redhat-release ]; then
  OS=CentOS
  if [ -n "$(grep ' 7\.' /etc/redhat-release)" ]; then
    CentOS_RHEL_version=7
  elif [ -n "$(grep ' 6\.' /etc/redhat-release)" ] || [ -n "$(grep 'Aliyun Linux release6 15' /etc/issue)" ]; then
    CentOS_RHEL_version=6
  elif [ -n "$(grep ' 5\.' /etc/redhat-release)" ] || [ -n "$(grep 'Aliyun Linux release5' /etc/issue)" ]; then
    CentOS_RHEL_version=5
  fi
elif [ -n "$(grep 'Amazon Linux AMI release' /etc/issue)" ] || [ -e /etc/system-release ]; then
  OS=CentOS
  CentOS_RHEL_version=6
elif [ -n "$(grep 'bian' /etc/issue)" ] || [ "$(lsb_release -is 2>/dev/null)" == "Debian" ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Debian_version=$(lsb_release -sr | awk -F. '{print $1}')
elif [ -n "$(grep 'Deepin' /etc/issue)" ] || [ "$(lsb_release -is 2>/dev/null)" == "Deepin" ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Debian_version=$(lsb_release -sr | awk -F. '{print $1}')
elif [ -n "$(grep 'Kali GNU/Linux Rolling' /etc/issue)" ] || [ "$(lsb_release -is 2>/dev/null)" == "Kali" ]; then
  OS=Debian
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  if [ -n "$(grep 'VERSION="2016.*"' /etc/os-release)" ]; then
    Debian_version=8
  else
    echo "不支持此操作系统，请联系作者！"
    kill -9 $$
  fi
elif [ -n "$(grep 'Ubuntu' /etc/issue)" ] || [ "$(lsb_release -is 2>/dev/null)" == "Ubuntu" ] || [ -n "$(grep 'Linux Mint' /etc/issue)" ]; then
  OS=Ubuntu
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Ubuntu_version=$(lsb_release -sr | awk -F. '{print $1}')
  [ -n "$(grep 'Linux Mint 18' /etc/issue)" ] && Ubuntu_version=16
elif [ -n "$(grep 'elementary' /etc/issue)" ] || [ "$(lsb_release -is 2>/dev/null)" == "elementary" ]; then
  OS=Ubuntu
  [ ! -e "$(which lsb_release)" ] && { apt-get -y update; apt-get -y install lsb-release; clear; }
  Ubuntu_version=16
else
  echo "不支持此操作系统，请联系作者！"
  kill -9 $$
fi

# Uninstall fail2ban
if [ ${OS} == CentOS ]; then
  yum -y remove fail2ban
elif [ ${OS} == Ubuntu ] || [ ${OS} == Debian ]; then
  apt-get -y remove fail2ban
fi

# Remove fail2ban configuration
rm -rf /etc/fail2ban

echo "fail2ban已成功卸载。"
