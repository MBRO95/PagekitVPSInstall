#!/bin/bash

#Display welcome header
echo -e "\e[1mHello, Welcome to Pagekit Setup Script v1.0\e[0m"
echo -e "\e[1mThis script is inteded to be run on linux vps hosts\e[0m"
echo -e "\e[1m**MUST BE RUN WITH ROOT PRIVILEDGES**\e[0m"

#Query the user for unattended installation variables
#What should the sitename be?
echo -ne "\e[1mWhat is the site name? (yourwebsite.com or local test server name): \e[0m"
read sitename;
#Add default sitename if none specified
if [ -z $sitename ] ; then
	echo -e "\e[33mSite name not specified, pushing default name: \e[35mpagekit\e[0m"
	sitename="pagekit"
	fi
echo -e "\e[1mThe sitename is, \e[35m$sitename\e[0m"
#Confirm sitename
echo -ne "\e[1mIs that correct? (y/n): \e[0m"
read confirm;
if [ $confirm = "y" -o $confirm =  "Y" ] ; then
	echo -e "\e[32mSitename confirmed!\e[0m"
else
	echo -e "\e[31mSitename incorrect, Please run me again!\e[0m"
	exit
fi
#What should the MySQL root password be?
echo -ne "\e[1mWhat do you want the MySQL root password to be?\e[0m"
read -s mysqlrootpass;
echo
#Add default MySQL root password if none specified
if [ -z $mysqlrootpass ] ; then
	echo -e "\e[33mMySQL root password not specified, pushing default password: \e[35mp@SsW0Rd\e[0m"
	mysqlrootpass="p@SsW0Rd"
	mysqlrootpass_conf="p@SsW0Rd"
else
	echo -ne "\e[1mPlease confirm the MySQL root password: \e[0m"
	read -s mysqlrootpass_conf;
	echo
	#Confirm MySQL root password
	if [ $mysqlrootpass == $mysqlrootpass_conf ] ; then
		echo -e "\e[32mPasswords Match, ready to install!\e[0m"
	else
		echo -e "\e[31mPasswords Do Not Match, Please run me again!\e[0m"
		exit
	fi
fi

#UPDATE & UPGRADE THE SYSTEM
echo -e "\e[1;32mUPDATE & UPGRADE THE SYSTEM\e[0m"
apt-get -y update && apt-get -y upgrade

#INSTALL LOGISTICAL DEPENDENCIES (Python, GIT, Curl)
echo -e "\e[1;32mINSTALL LOGISTICAL DEPENDENCIES\e[0m"
apt-get install -y software-properties-common python-software-properties git curl

#INSTALL NGINX + PHP + EXTENSIONS
echo -e "\e[1;32mINSTALL NGINX + PHP + EXTENSIONS\e[0m"
apt-get install -y nginx php5-fpm php5-cli php5-mysql php5-curl php5-json php5-apcu

#INSTALL COMPOSER
echo -e "\e[1;32mINSTALL COMPOSER\e[0m"
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

#INSTALL NODE + BOWER + GULP
echo -e "\e[1;32mINSTALL NODE + BOWER + GULP\e[0m"
curl -sL https://deb.nodesource.com/setup | sudo bash - #Trying Node Update: curl -sL https://deb.nodesource.com/setup_0.12 | sudo bash -
apt-get install -y nodejs
npm cache clean
npm install -g bower
npm install -g gulp

#CLONE PAGEKIT LOCALLY
echo -e "\e[1;32mCLONE PAGEKIT LOCALLY\e[0m"
#Create website directory
mkdir -p /usr/share/nginx/$sitename/{public_html,logs}
#Implement download and extract of this version, as it was working in September
#Most recent version is running into multiple errors, rolling back for support
wget https://github.com/pagekit/pagekit/releases/download/0.9.1/pagekit-0.9.1.zip -P /usr/share/nginx/$sitename/public_html/
cd /usr/share/nginx/$sitename/public_html
apt-get install -y unzip
unzip pagekit*.zip
rm pagekit*.zip
composer install
npm install
bower install --allow-root
gulp

#CONFIGURE NGINX
echo -e "\e[1;32mCONFIGURE NGINX\e[0m"
serverBlock="/etc/nginx/sites-available/$sitename"
#Write dynamic serverBlock (utilizing unattended install variables) to file for NGINX configuration
tee  $serverBlock > /dev/null <<EOF
server {
	server_name $sitename;
	listen 80;
	listen [::]:80;
	root /usr/share/nginx/$sitename/public_html;
	access_log /usr/share/nginx/$sitename/logs/access.log;
	error_log /usr/share/nginx/$sitename/logs/error.log;
	index index.php;
	server_name locahost;
 
	location / {
    	try_files \$uri \$uri/ /index.php?\$args;
	}
 
	location ~* \.(?:ico|css|js|gif|jpe?g|png|ttf|woff)$ {
    	access_log off;
    	expires 30d;
        	add_header Pragma public;
        	add_header Cache-Control "public, mustrevalidate, proxy-revalidate";
	}
 
    	location ~ \.php$ {
        	fastcgi_index index.php;
        	fastcgi_split_path_info ^(.+\.php)(.*)$;
        	fastcgi_keep_conn on;
        	include /etc/nginx/fastcgi_params;
        	fastcgi_pass unix:/var/run/php5-fpm.sock;
        	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    	}
 
    	location ~ /\.ht {
       		deny all;
    	}
 
}
EOF

#INSTALL MySQL & CREATE PAGEKIT DATABASE
echo -e "\e[1;32mINSTALL MySQL & CREATE PAGEKIT DATABASE\e[0m"
#Close down frontend fucntionality
export DEBIAN_FRONTEND="noninteractive"
#Push unattended install variables to file
mkdir /root/src
touch /root/src/debconf.txt
echo "mysql-server mysql-server/root_password password $mysqlrootpass" >> /root/src/debconf.txt
echo "mysql-server mysql-server/root_password_again password $mysqlrootpass_conf" >> /root/src/debconf.txt
#Tell installer to pull info from variables in file
debconf-set-selections /root/src/debconf.txt
#Install MySQL server
apt-get -y install mysql-server
#Secure MySQL Installation
echo -e "\e[1;32mSECURE MySQL\e[0m"
#Set up mysql_secure_installation for unattended setup
apt-get -y install expect
cd ~/
expectBlock="mysqlsecure.expect"
tee  $expectBlock > /dev/null <<EOF
spawn mysql_secure_installation
expect "Enter current password for root (enter for none):"
	send "$mysqlrootpass\r"
expect "Set root password?"
	send "n\r"
expect "Remove anonymous users?"
	send "y\r"
expect "Disallow root login remotely?"
	send "y\r"
expect "Remove test database and access to it?"
	send "y\r"
expect "Reload privilege tables now?"
	send "y\r"
puts "Execution Complete"
EOF
#Execute mysql_secure_installation unattended
expect -f ~/mysqlsecure.expect

#CREATE PAGEKIT DATABASE
mysql --host=localhost --user=root --password=$mysqlrootpass << END

CREATE DATABASE pagekit;
GRANT ALL PRIVILEGES ON pagekit.* TO 'pagekituser'@'localhost' IDENTIFIED BY 'pagekituser_passwd';
FLUSH PRIVILEGES;

END

#TEST CONFIG, SYMLINK, REMOVE DEFAULTS, CHOWN WWW-DATA, RESTART NGINX
echo -e "\e[1;32mTEST CONFIG, SYMLINK, REMOVE DEFAULTS, CHOWN WWW-DATA, RESTART NGINX\e[0m"
sudo nginx -t
ln -s /etc/nginx/sites-available/$sitename /etc/nginx/sites-enabled/$sitename
rm /etc/nginx/sites-available/default -rf
rm /etc/nginx/sites-enabled/default -rf
rm /usr/share/nginx/html -rf
chown -R www-data: /usr/share/nginx/$sitename/public_html/
/etc/init.d/nginx restart

#WE HAVE COMPLETED ALL NECESSARY STEPS, CLEANLY PRESENT SITE TO USER
#Pull external IP
IP_ADDR="$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//')"
echo
#Echo setup URL to terminal
echo -e "\e[1mPlease navigate to:\e[0m \e[4;32mhttp://${IP_ADDR}/installer\e[0m"