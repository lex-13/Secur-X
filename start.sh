#!/bin/bash

# Secur-X v1.0
#
# f13
# www.jasonsoto.com
# www.jsitech-sec.com
# Twitter = @JsiTech

# Based from JShielder Project
# Credits to Jason Soto

# Suggestions from the Raspberry Pi Hardening Guide by chrisapproved
# https://chrisapproved.com/blog/raspberry-pi-hardening.html
# Credits to Chris

source src/helpers.sh

if [ "$USER" != "root" ]; then
    echo "Permission Denied"
    echo "Can only be run by root"
    exit
fi

echo
cat << "EOF"
                                                            
 ,---.  ,------. ,-----.,--. ,--.,------.       ,--.   ,--. 
'   .-' |  .---''  .--./|  | |  ||  .--. ',-----.\  `.'  /  
`.  `-. |  `--, |  |    |  | |  ||  '--'.''-----' .'    \   
.-'    ||  `---.'  '--'\'  '-'  '|  |\  \        /  .'.  \  
`-----' `------' `-----' `-----' `--' '--'      '--'   '--' 
                                                            
For Ubuntu Server 20.04 LTS
Made with ❤ by yours truly f13
EOF
echo

script_home=$(pwd)
serverip=$(__get_ip)

update_system(){
    echo -e "\e[93m[+]\e[00m Updating the System"
    apt-get update
    apt-get upgrade -y
}
create_backup() {
    echo -e "\e[93m[+]\e[00m Creating a backup of files to be modified"
    mkdir -p backups
    backup_dir="backups/$(date +'%F_%H-%M-%S')"
    mkdir $backup_dir
    cp /etc/hosts  --parents ./$backup_dir
}
config_host() {
    host_name=$(no_blank "server name (ex. myserver): ")
    domain_name=$(no_blank "domain name (ex. example.com): ")
    hostnamectl set-hostname $host_name.$domain_name
    local host_ip=$(cat /etc/hosts | grep -v -e "localhost" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
    echo "$host_ip   $host_name.$domain_name " >> /etc/hosts
    echo "127.0.0.1   localhost" >> /etc/hosts
    if test -f "/etc/cloud/cloud.cfg"; then
        echo -e "\e[93m[+]\e[00m Warning! /etc/cloud/cloud.cfg exists. attempting to patch"
        sed -i -e 's/preserve_hostname: false/preserve_hostname: true/g' /etc/cloud/cloud.cfg
    fi
}
new_admin() {
    echo -e "\e[93m[+]\e[00m Creating a new admin user"
    getent group ssh-users || groupadd ssh-users
    username=$(no_blank "username: ")
    adduser $username
    usermod -aG sudo $username
    usermod -aG ssh-users $username
    echo
    echo "************ SSH KEYS SETUP ************"
    echo "Generate and copy the keys to the server"
    echo "(recommend ed25519 cipher)"
    echo "Run the following on your client (enter):"
    echo -n "- ssh-keygen -t ed25519 -a 777"; read foo1
    echo -n "- ssh-copy-id -i <public key> $username@$serverip"; read foo2
}
secure_ssh() {
    echo -e "\e[93m[+]\e[00m Securing SSH"
    cp src/config/sshd_config /etc/ssh/sshd_config
    systemctl restart ssh
}
enable_ufw() {
    echo -e "\e[93m[+]\e[00m Installing ufw"
    apt install ufw -y
    ufw default deny incoming
    ufw default allow outgoing
    ufw limit ssh
    ufw allow http
    ufw allow https
    ufw logging on
    ufw enable
}
install_fail2ban() {
    echo -e "\e[93m[+]\e[00m Installing fail2ban"
    apt install fail2ban -y
    cp src/config/jail.conf /etc/fail2ban/jail.local
    service fail2ban restart
    cp src/config/nginx-noscript.conf /etc/fail2ban/filter.d/nginx-noscript.conf
    cp /etc/fail2ban/filter.d/apache-badbots.conf /etc/fail2ban/filter.d/nginx-badbots.conf
    service fail2ban restart
}
install_psad() {
    echo -e "\e[93m[+]\e[00m Installing fail2ban"
    echo "Enter your email(s) separated by a comma"
    local emails=$(no_blank "email(s): ")
    apt install psad -y
    sed -i s/INBOX/$emails/g src/config/psad.conf
    sed -i s/CHANGEME/$host_name.$domain_name/g templates/psad.conf  
    cp src/config/psad.conf /etc/psad/psad.conf
    cp src/config/before.rules /etc/ufw/before.rules
    cp src/config/before6.rules /etc/ufw/before6.rules
    ufw reload
    psad -R
    psad --sig-update
    psad -H
}
install_nginx(){
    echo -e "\e[93m[+]\e[00m Installing NginX Web Server"
    echo "deb http://nginx.org/packages/ubuntu/ focal nginx" >> /etc/apt/sources.list
    echo "deb-src http://nginx.org/packages/ubuntu/ focal nginx" >> /etc/apt/sources.list
    curl -O https://nginx.org/keys/nginx_signing.key && apt-key add ./nginx_signing.key
    apt update
    apt install nginx -y
    systemctl enable nginx
    systemctl start nginx
}
confirm_yes "Update system?" && update_system
# confirm_yes "Create backup of config files?" && create_backup
get_yes_keypress "Set HostName? (y/n): " && config_host
new_admin
secure_ssh
enable_ufw
install_fail2ban
install_psad
install_nginx

echo -e "\e[32m[✔]\e[00m Hardening completed successfully"
echo "Use the following command to access the server:"
echo -e "ssh -i <private key> $username@$serverip"