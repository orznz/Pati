#!/bin/bash
function blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
function green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
function red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
function version_lt(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; 
}

if [ `id -u` -ne 0 ]; then
    blue "The script must be executed as root. First execute 'sudo su' to become root and then execute the script."
    exit 1
fi

if [[ -f /etc/redhat-release ]]; then
    release="centos"
    systemPackage="yum"
elif grep -Eqi "debian|raspbian|ubuntu" /etc/issue; then
    release="debian"
    systemPackage="apt-get"
elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
    release="centos"
    systemPackage="yum"
elif grep -Eqi "debian|raspbian|ubuntu" /proc/version; then
    release="debian"
    systemPackage="apt-get"
elif grep -Eqi "centos|red hat|redhat" /proc/version; then
    release="centos"
    systemPackage="yum"
else
    red "System type not detected, installation failed! Please check if your system is supported."
    exit 1
fi

systempwd="/etc/systemd/system/"

function install_trojan(){
    $systemPackage install -y nginx  >/dev/null 2>&1
    if [ ! -d "/etc/nginx/" ]; then
        red "There seems to be an issue with the nginx installation. Please uninstall it and install nginx manually before attempting to install Trojan-Go again."
	red "Providing feedback here is both recommended and appreciated: https://github.com/orznz/Pati/issues/new/choose"
        exit 1
    fi
    if [ ! -f "/etc/nginx/mime.types" ]; then
        wget https://raw.githubusercontent.com/nginx/nginx/master/conf/mime.types -O /etc/nginx/mime.types
    fi
    if [ ! -f "/etc/nginx/mime.types" ]; then
        red "There seems to be an issue with /etc/nginx/mime.types. Please uninstall Trojan-Go and reinstall it again."
		exit 1
    fi
    cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    server {
        listen       80;
        server_name  $your_domain;
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
    }
}
EOF
    systemctl restart nginx >/dev/null 2>&1
    sleep 3
    green "Clearing the folder /usr/share/nginx/html/ and downloading the fake website."
    rm -rf /usr/share/nginx/html/*
    cd /usr/share/nginx/html/
    wget https://github.com/orznz/Pati/raw/main/fakesite.zip >/dev/null 2>&1
    green "Fake website downloaded successfully, starting the decompression process."
    unzip fakesite.zip >/dev/null 2>&1
    sleep 5
    mkdir /usr/src/trojan-cert/$your_domain -p
    green "Decompression successful. Initiating certificate request process."
    issue_cert
    green "Certificate request successful."
     
    cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    server {
        listen       127.0.0.1:80;
        server_name  $your_domain;
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
    }
    server {
        listen       0.0.0.0:80;
        server_name  $your_domain;
    
    location  /aria {
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
        }
        
    location  / {
            return 301 https://$your_domain\$request_uri;
            }
        
    }
    
}
EOF
    systemctl restart nginx  >/dev/null 2>&1
    systemctl enable nginx  >/dev/null 2>&1
    cd /usr/src
    wget https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest >/dev/null 2>&1
    latest_version=`grep tag_name latest| awk -F '[:,"v]' '{print $6}'`
    rm -f latest
    green "Downloading the latest version of Trojan-Go for amd64 architecture."
    wget https://github.com/p4gefau1t/trojan-go/releases/download/v${latest_version}/trojan-go-linux-amd64.zip >/dev/null 2>&1
    unzip trojan-go-linux-amd64.zip -d trojan-go >/dev/null 2>&1
    rm -f trojan-go-linux-amd64.zip
    rm -rf ./trojan-go/example
    green "Set a password for Trojan-Go. It is recommended to avoid using special characters such as @ and #."
    read -p "Enter password:" trojan_passwd

    rm -rf /usr/src/trojan-go/server.json
    cat > /usr/src/trojan-go/server.json <<-EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "log_level": 1,
  "log_file": "",
  "password": ["$trojan_passwd"],
  "disable_http_check": false,
  "udp_timeout": 60,
  "ssl": {
    "verify": true,
    "verify_hostname": true,
    "cert": "/usr/src/trojan-cert/$your_domain/fullchain.cer",
    "key": "/usr/src/trojan-cert/$your_domain/private.key",
    "key_password": "",
    "cipher": "",
    "curves": "",
    "prefer_server_cipher": false,
    "sni": "",
    "alpn": [
      "http/1.1"
    ],
    "session_ticket": true,
    "reuse_session": true,
    "plain_http_response": "",
    "fallback_addr": "",
    "fallback_port": 0,
    "fingerprint": ""
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "prefer_ipv4": false
  },
  "mux": {
    "enabled": false,
    "concurrency": 8,
    "idle_timeout": 60
  },
  "router": {
    "enabled": false,
    "bypass": [],
    "proxy": [],
    "block": [],
    "default_policy": "proxy",
    "domain_strategy": "as_is",
    "geoip": "/usr/src/trojan-go/geoip.dat",
    "geosite": "/usr/src/trojan-go/geosite.dat"
  },
  "websocket": {
    "enabled": false,
    "path": "",
    "host": ""
  },
  "mysql": {
    "enabled": false,
    "server_addr": "localhost",
    "server_port": 3306,
    "database": "",
    "username": "",
    "password": "",
    "check_rate": 60
  }
}
EOF
    cat > ${systempwd}trojan-go.service <<-EOF
[Unit]  
Description=trojan-go  
After=network.target  
   
[Service]  
Type=simple  
PIDFile=/usr/src/trojan-go/trojan-go/trojan-go.pid
ExecStart=/usr/src/trojan-go/trojan-go -config "/usr/src/trojan-go/server.json"  
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=1s
   
[Install]  
WantedBy=multi-user.target
EOF

    chmod +x ${systempwd}trojan-go.service
    systemctl enable trojan-go.service >/dev/null 2>&1
    cd /root
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /usr/src/trojan-cert/$your_domain/private.key \
        --fullchain-file  /usr/src/trojan-cert/$your_domain/fullchain.cer \
        --reloadcmd  "systemctl restart trojan-go"  >/dev/null 2>&1   
    green "Trojan-Go has been installed successfully!"
    showme_sub

}
function preinstall_check(){

    nginx_status=`ps -aux | grep "nginx: worker" |grep -v "grep"`
    if [ -n "$nginx_status" ]; then
        systemctl stop nginx
    fi
    $systemPackage -y install net-tools socat unzip >/dev/null 2>&1
    Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
    Port443=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 443`
    if [ -n "$Port80" ]; then
        process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
        red "Port 80 is occupied by process ${process80}. Installation terminates."
        exit 1
    fi
    if [ -n "$Port443" ]; then
        process443=`netstat -tlpn | awk -F '[: ]+' '$5=="443"{print $9}'`
        red "Port 443 is occupied by process ${process443}. Installation terminates."
        exit 1
    fi
    if [ -f "/etc/selinux/config" ]; then
        CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
        if [ "$CHECK" == "SELINUX=enforcing" ]; then
            green "$(date +"%Y-%m-%d %H:%M:%S") - The current SELinux status is not \"disabled\" and has been disabled now."
            setenforce 0
            sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        elif [ "$CHECK" == "SELINUX=permissive" ]; then
            green "$(date +"%Y-%m-%d %H:%M:%S") - The current SELinux status is not \"disabled\" and has been disabled now."
            setenforce 0
            sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
        fi
    fi
    if [ "$release" == "centos" ]; then
        firewall_status=`systemctl status firewalld | grep "Active: active"`
        if [ -n "$firewall_status" ]; then
            green "Firewalld is detected as enabled. Adding rules to allow traffic on ports 80 and 443."
            firewall-cmd --zone=public --add-port=80/tcp --permanent  >/dev/null 2>&1
            firewall-cmd --zone=public --add-port=443/tcp --permanent  >/dev/null 2>&1
            firewall-cmd --reload  >/dev/null 2>&1
        fi
    elif [ "$release" == "debian" ]; then
        ufw_status=`systemctl status ufw | grep "Active: active"`
        if [ -n "$ufw_status" ]; then
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw reload
        fi
        apt-get update
    elif [ "$release" == "debian" ]; then
        ufw_status=`systemctl status ufw | grep "Active: active"`
        if [ -n "$ufw_status" ]; then
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw reload
        fi
        apt-get update
    fi
    $systemPackage -y install  wget unzip zip curl tar >/dev/null 2>&1
    blue "Please enter the domain name that has been resolved to this server."
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl -s ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        green "Domain name resolution is available. Trojan installation is now starting."
        sleep 1s
        install_trojan
    else
        red "The domain name resolution is not correct."
        red "You may force the script to continue if you confirm that the domain name resolution is correct."
        read -p "Do you want to force the execution? [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Yy] ]]; then
            green "Resuming script execution forcefully."
            sleep 1s
            install_trojan
        else
            exit 1
        fi
    fi
}

function issue_cert(){
    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh  --register-account  -m test@$your_domain --server zerossl >/dev/null 2>&1
    ~/.acme.sh/acme.sh  --issue  -d ${your_domain}  --nginx >/dev/null 2>&1
    ret=`~/.acme.sh/acme.sh --info -d ${your_domain} | grep "Le_Domain=${your_domain}"`
    if [ ret = "" ] ; then
        red "SSL certificate application failed. Please uninstall to clean up the previously installed files."
        exit 1
    fi
}


function repair_cert(){
    systemctl stop nginx
    Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
    if [ -n "$Port80" ]; then
        process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
        red "Port 80 is occupied by process ${process80}. Installation terminates."
        exit 1
    fi
    blue "Please enter the domain name that resolves to this machine."
    blue "Make sure that it is the same as the domain name used in the previous unsuccessful attempt."
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        ~/.acme.sh/acme.sh  --register-account  -m test@$your_domain --server zerossl
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
        ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
            --key-file   /usr/src/trojan-cert/$your_domain/private.key \
            --fullchain-file /usr/src/trojan-cert/$your_domain/fullchain.cer \
            --reloadcmd  "systemctl restart trojan-go"
        if test -s /usr/src/trojan-cert/$your_domain/fullchain.cer; then
            green "Certificate application successful."
            systemctl restart trojan-go
            systemctl start nginx
        else
            red "Certificate application failed."
        fi
    else
        red "Domain resolution address does not match the IP address of this VPS. Installation failed. Please ensure that domain resolution is correct."
    fi
}

function remove_trojan(){
    red "Trojan-go will be uninstalled and nginx installed will also be removed shortly."
    systemctl stop trojan-go
    systemctl disable trojan-go
    systemctl stop nginx
    systemctl disable nginx
    rm -f ${systempwd}trojan-go.service
    if [ "$release" == "centos" ]; then
        yum remove -y nginx  >/dev/null 2>&1
    else
        apt-get -y autoremove nginx
        apt-get -y --purge remove nginx
        apt-get -y autoremove && apt-get -y autoclean
        find / | grep nginx | sudo xargs rm -rf
    fi
    rm -rf /usr/src/trojan-go/
    rm -rf /usr/src/trojan-cert/
    rm -rf /usr/share/nginx/html/*
    rm -rf /etc/nginx/
    # rm -rf /root/.acme.sh/
    green "=============="
    green "Trojan-go uninstalled successfully."
    green "=============="
}

function update_trojan(){
    /usr/src/trojan-go/trojan-go -version >trojan-go.tmp
    curr_version=`cat trojan-go.tmp | grep "Trojan-Go" | awk '$2~/^v[0-9].*/{print substr($2,2)}'`
    wget https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest >/dev/null 2>&1
    latest_version=`grep tag_name latest| awk -F '[:,"v]' '{print $6}'`
    rm -f latest
    rm -f trojan-go.tmp
    if version_lt "$curr_version" "$latest_version"; then
        green "Current version: $curr_version. Latest version: $latest_version. Starting upgrade..."
        mkdir trojan-go_update_temp && cd trojan-go_update_temp
        wget https://github.com/p4gefau1t/trojan-go/releases/download/v${latest_version}/trojan-go-linux-amd64.zip
        unzip trojan-go-linux-amd64.zip -d trojan-go >/dev/null 2>&1
        rm -rf ./trojan-go/example
        mv -f ./trojan-go/* /usr/src/trojan-go/
        cd .. && rm -rf trojan-go_update_temp
        systemctl restart trojan-go
    /usr/src/trojan-go/trojan-go -version >trojan-go.tmp
    green "Server upgrade is complete.Current version:`cat trojan-go.tmp | grep "Trojan-Go" | awk '$2~/^v[0-9].*/{print substr($2,2)}'`"
    rm -f trojan-go.tmp
    else
        green "Current version:$curr_version,latest version:$latest_version,no upgrade required."
    fi
    
}

function install_ss(){
    blue "Server port"
    read ss_port
    green "======================="
    blue "Password"
    green "======================="
    read ss_password
    $systemPackage install net-tools -y
    wait
    PortSS=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w ${ss_port}`
    if [ -n "$PortSS" ]; then
        processSS=`netstat -tlpn | awk -F '[: ]+' -v port=$PortSS '$5==port{print $9}'`
        red "Port ${PortSS} is occupied by process ${processSS}. Installation terminates."
        exit 1
    fi
    if [ "$release" == "centos" ]; then
        firewall_status=`systemctl status firewalld | grep "Active: active"`
        if [ -n "$firewall_status" ]; then
            green "Firewalld is detected to be enabled. Adding rule to allow port ${ss_port}."
            firewall-cmd --zone=public --add-port=$ss_port/tcp --permanent
            firewall-cmd --reload
        fi
        $systemPackage install epel-release -y
        $systemPackage clean all
        $systemPackage makecache
        $systemPackage update -y
        $systemPackage install git gcc glibc-headers gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel -y
    elif [ "$release" == "debian" ]; then
        ufw_status=`systemctl status ufw | grep "Active: active"`
        if [ -n "$ufw_status" ]; then
            ufw allow $ss_port/tcp
            ufw reload
        fi
        $systemPackage update -y
        $systemPackage install -y --no-install-recommends git libssl-dev gettext build-essential autoconf libtool libpcre3 libpcre3-dev asciidoc xmlto libev-dev libc-ares-dev automake libmbedtls-dev libsodium-dev pkg-config
    fi
    if [ ! -d "/usr/src" ]; then
        mkdir /usr/src
    fi
    if [ ! -d "/usr/src/ss" ]; then
        mkdir /usr/src/ss
    fi
    cd /usr/src/ss
    git clone https://github.com/shadowsocks/shadowsocks-libev.git
    cd shadowsocks-libev
    git submodule update --init --recursive
    ./autogen.sh && ./configure && make
    make install
    if [ ! -d "/usr/src" ]; then
        mkdir /usr/src
    fi
    if [ ! -d "/usr/src/ss" ]; then
        mkdir /usr/src/ss
    fi
    rm -rf /usr/src/ss/ss-config
    cat > /usr/src/ss/ss-config <<-EOF
{
    "server": "0.0.0.0",
    "server_port": $ss_port,
    "local_port": 1080,
    "password": "$ss_password",
    "timeout": 600,
    "method": "chacha20-ietf-poly1305"
}
EOF
    cat > ${systempwd}ss.service <<-EOF
[Unit]  
Description=ShadowsSocks Server 
After=network.target  
   
[Service]  
Type=simple  
PIDFile=/usr/src/ss/ss.pid
ExecStart=nohup /usr/local/bin/ss-server -c /usr/src/ss/ss-config &  
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=1s
   
[Install]  
WantedBy=multi-user.target
EOF
    chmod +x ${systempwd}ss.service
    systemctl enable ss.service
    systemctl restart ss
}

function remove_ss(){
    red "Shadowsocks will be uninstalled shortly."
    red "Dependencies installed previously will not be uninstalled to prevent accidental removal. You may decide whether to remove them manually, such as net-tools and git."
    systemctl stop ss
    systemctl disable ss
    rm -f ${systempwd}ss.service
    cd /usr/src/ss/shadowsocks-libev
    make uninstall
    rm -rf /usr/src/ss/
    green "Shadowsocks successfully uninstalled."
}

function install_ss_rust(){
    blue "Server port"
    read ss_port
    blue "Password"
    read ss_password
    $systemPackage install net-tools -y
    wait
    PortSS=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w ${ss_port}`
    if [ -n "$PortSS" ]; then
        processSS=`netstat -tlpn | awk -F '[: ]+' -v port=$PortSS '$5==port{print $9}'`
        red "==========================================================="
        red "Port ${PortSS} is occupied by process ${processSS}. Installation terminates."
        red "==========================================================="
        exit 1
    fi
    if [ "$release" == "centos" ]; then
        firewall_status=`systemctl status firewalld | grep "Active: active"`
        if [ -n "$firewall_status" ]; then
            green "Firewalld is detected to be enabled. Adding rule to allow port ${ss_port}."
            firewall-cmd --zone=public --add-port=$ss_port/tcp --permanent
            firewall-cmd --reload
        fi
    elif [ "$release" == "debian" ]; then
        ufw_status=`systemctl status ufw | grep "Active: active"`
        if [ -n "$ufw_status" ]; then
            ufw allow $ss_port/tcp
            ufw reload
        fi
    fi
    if [ ! -d "/usr/src" ]; then
        mkdir /usr/src
    fi
    if [ ! -d "/usr/src/ss-rust" ]; then
        mkdir /usr/src/ss-rust
    fi
    cd /usr/src/ss-rust
    wget https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest >/dev/null 2>&1
    latest_version=`grep tag_name latest| awk -F '[:,"v]' '{print $6}'`
    rm -f latest
    green "Downloading latest version of Shadowsocks-rust."
    wget https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${latest_version}/shadowsocks-v${latest_version}.x86_64-unknown-linux-gnu.tar.xz -O ss-rust.tar.xz 
    tar -xvf ss-rust.tar.xz
    chmod +x ssserver
    rm -rf /usr/src/ss-rust/ss-config
    cat > /usr/src/ss-rust/ss-config <<-EOF
{
    "server": "0.0.0.0",
    "server_port": $ss_port,
    "local_port": 1080,
    "password": "$ss_password",
    "timeout": 600,
    "method": "chacha20-ietf-poly1305"
}
EOF
    cat > ${systempwd}ss.service <<-EOF
[Unit]  
Description=ShadowsSocks-rust Server 
After=network.target  
   
[Service]  
Type=simple  
PIDFile=/usr/src/ss-rust/ss.pid
ExecStart=/usr/src/ss-rust/ssserver -c "/usr/src/ss-rust/ss-config" 
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=1s
   
[Install]  
WantedBy=multi-user.target
EOF
    chmod +x ${systempwd}ss.service
    systemctl enable ss.service
    systemctl restart ss
}

function remove_ss_rust(){
    red "Shadowsocks-rust will be uninstalled shortly."
    red "Dependencies installed previously will not be uninstalled to prevent accidental removal. You may decide whether to remove them manually, such as net-tools."
    systemctl stop ss
    systemctl disable ss
    rm -f ${systempwd}ss.service
    rm -rf /usr/src/ss-rust/
    green "Shadowsocks-rust successfully uninstalled."
}

function showme_sub(){
    port=`cat /usr/src/trojan-go/server.json | grep local_port | awk -F '[,]+|[ ]' '{ print $(NF-1) }'`
    domain=`cat /usr/src/trojan-go/server.json | grep private.key | awk -F / '{ print $(NF-1) }'`
    password=`cat /usr/src/trojan-go/server.json | grep password | head -n 1 | awk -F '["]' '{ print $(NF-1) }'`
    red "The following are just ordinary node subscription links. If you are using software such as Clash, please convert them yourself."
    blue "Your Trojan subscription link is:trojan://${password}@${domain}:${port}"
}

start_menu(){
    # clear
    green " ===========================Pátī========================="
    green " Introduction: One-click installation of Trojan-Go and Shadowsocks."
    green " Supported: Red Hat/CentOS/AlmaLinux/RockyLinux/Debian/Ubuntu."
    green " Project: https://github.com/orznz/Pati             "
    red " Attention:"
    red " *1. Do not use this script in any production environment."
    red " *2. The script will directly modify the Nginx configuration and clear the /usr/share/nginx/html/ directory!"
    red " *3. Do not occupy ports 80 and 443."
    red " *4. If you use the script to install for the second time, please execute the uninstallation script first."
    green " ========================================================"
    echo
    green " 1. Install Trojan-Go (strongly recommended)"
    red " 2. Uninstall Trojan-Go"
    green " 3. Upgrade Trojan-Go"
    green " 4. Fix SSL certificates"
    green " 5. Install ShadowSocks-libev"
    red " 6. Uninstall ShadowSocks-libev"
    green " 7. Install ShadowSocks-rust (recommended)"
    red " 8. Uninstall ShadowSocks-rust"
    green " 9. Show subscription link."
    blue " 0. Exit"
    echo
    read -p "Please enter a number:" num
    case "$num" in
    1)
    preinstall_check
    ;;
    2)
    remove_trojan 
    ;;
    3)
    update_trojan 
    ;;
    4)
    repair_cert 
    ;;
    5)
    install_ss 
    ;;
    6)
    remove_ss 
    ;;
    7)
    install_ss_rust 
    ;;
    8)
    remove_ss_rust 
    ;;
    9)
    showme_sub 
    ;;
    0)
    exit 1
    ;;
    *)
    # clear
    red "Choose your option"
    sleep 1s
    start_menu
    ;;
    esac
}

start_menu
