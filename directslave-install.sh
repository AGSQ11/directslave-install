#!/bin/sh
# @author jordavin,phillcoxon,mantas15
# @updated by Afrizal-id
# @updated later by osmanboy / ericosman @forum.directadmin.com
# @updated for Ubuntu by AGSQ
# @date 20.12.2024
# @version 1.0.7

sshport=22;

# Check root user
if [ "$(id -u)" != "0" ]; then
    printf "Sorry, This script must be run as root\n"
    exit 1
fi

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "usage <username> <userpass> <master ip>";
    exit 0;
fi

echo "Saving most outputs to /root/install.log";

echo "doing updates and installs"
apt-get update -y > /root/install.log
apt-get upgrade -y >> /root/install.log
apt-get install bind9 bind9utils wget -y >> /root/install.log

systemctl start bind9 >> /root/install.log
systemctl stop bind9 >> /root/install.log

echo "creating user "$1" and adding to sudo group"
useradd -m -G sudo $1 > /root/install.log
echo "$1:$2" | chpasswd >> /root/install.log

echo "Disabling root access to ssh use "$1"."
echo -n "Enter SSH port to change (recommended) from ${sshport}: "
read customsshport
if [ $customsshport ]; then
    sshport=$customsshport
fi
echo "Your ssh port is ${sshport}"
sed -i '/PermitRootLogin/ c\PermitRootLogin no' /etc/ssh/sshd_config
sed -i -e "s/#Port 22/Port ${sshport}/g" /etc/ssh/sshd_config
sed -i -e 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config
systemctl restart ssh >> /root/install.log

echo "installing and configuring directslave"
cd ~
wget -q https://github.com/osmanboy/directslave-install/raw/master/directslave-3.4.3-advanced-all.tar.gz >> /root/install.log
tar -xf directslave-3.4.3-advanced-all.tar.gz
mv directslave /usr/local/
cd /usr/local/directslave/bin
mv directslave-linux-amd64 directslave
cd /usr/local/directslave/
chown bind:bind -R /usr/local/directslave

curip="$( hostname -I|awk '{print $1}' )"
cat > /usr/local/directslave/etc/directslave.conf <<EOF
background	1
host            $curip
port            2222
ssl             off
cookie_sess_id  DS_SESSID
cookie_auth_key Change_this_line_to_something_long_&_secure
debug           0
uid             102
gid             102
pid             /usr/local/directslave/run/directslave.pid
access_log	/usr/local/directslave/log/access.log
error_log	/usr/local/directslave/log/error.log
action_log	/usr/local/directslave/log/action.log
named_workdir   /etc/bind/secondary
named_conf	/etc/bind/directslave.inc
retry_time	1200
rndc_path	/usr/sbin/rndc
named_format    text
authfile        /usr/local/directslave/etc/passwd
EOF

mkdir -p /etc/bind/secondary
touch /etc/bind/secondary/named.conf
touch /etc/bind/directslave.inc
chown bind:bind -R /etc/bind
mkdir -p /var/log/named
touch /var/log/named/security.log
chmod a+w -R /var/log/named

cat > /etc/bind/named.conf.options <<EOF
options {
	directory "/var/cache/bind";
	listen-on port 53 { any; };
	listen-on-v6 { none; };
        allow-query     { any; };
        allow-notify	{ $3; };
        allow-transfer	{ $3; };
	recursion no;
	dnssec-validation auto;
	auth-nxdomain no;
};
EOF

cat > /etc/bind/named.conf.local <<EOF
include "/etc/bind/directslave.inc";
EOF

touch /usr/local/directslave/etc/passwd
chown bind:bind /usr/local/directslave/etc/passwd
/usr/local/directslave/bin/directslave --password $1:$2
/usr/local/directslave/bin/directslave --check >> /root/install.log
rm -f /usr/local/directslave/run/directslave.pid

cat > /etc/systemd/system/directslave.service <<EOL
[Unit]
Description=DirectSlave for DirectAdmin
After=network.target

[Service]
Type=simple
User=bind
ExecStart=/usr/local/directslave/bin/directslave --run
Restart=always

[Install]
WantedBy=multi-user.target
EOL

echo "setting enabled and starting up"
chown root:root /etc/systemd/system/directslave.service
chmod 755 /etc/systemd/system/directslave.service
systemctl daemon-reload >> /root/install.log
systemctl enable bind9 >> /root/install.log
systemctl enable directslave >> /root/install.log
systemctl restart bind9 >> /root/install.log
systemctl restart directslave >> /root/install.log

echo "configuring UFW firewall"
apt-get install ufw -y >> /root/install.log
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 2222/tcp
ufw allow $sshport/tcp
ufw allow 443/tcp
ufw --force enable

echo "Checking DirectSlave and starting"
/usr/local/directslave/bin/directslave --check
/usr/local/directslave/bin/directslave --run

echo "all done!"
echo "Open the DirectSlave Dashboard using a web browser http://$curip:2222"
echo "if failed browse using IP address, edit /usr/local/directslave/etc/directslave.conf and change the host 127.0.0.1 to your current IP address"
exit 0;
