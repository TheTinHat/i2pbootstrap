#!/bin/sh

TMPFILE=$(mktemp)
sshport=2121

# This isn't strictly necessary, but wth.
wait_until() {
    local timeout check_expr delay timeout_at
    timeout="${1}"
    check_expr="${2}"
    delay="${3:-1}"
    timeout_at=$(expr $(date +%s) + ${timeout})
    until eval "${check_expr}"; do
        if [ "$(date +%s)" -ge "${timeout_at}" ]; then
            return 1
        fi
        sleep ${delay}
    done
    return 0
}

help() {
	echo "Usage: $0 [-h] [-p ssh-port]"
	echo ""
	echo "Options:"
	echo "-h               Display this help menu."
	echo "-p [ssh-port]    The port to use for SSH connections"
	exit 1
}

#Check Root
if [ `id -u ` -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi


while getopts "hp:" Option
do
	case $Option in
	h) help;;
	p) sshport=$OPTARG ;;
	esac
done

#we don't want to allow an unusable port.
if [ $sshport -lt 0 -o $sshport -gt 65535 ]; then
	echo "Bad port number, must be between 0 and 65535."
	exit 1
fi


#Disclaimers
echo "Warning: Ensure that a separate user account has been created already.">&2
echo "This account CANNOT be called i2psvc. This script will disable logging in">&2
echo "as the root user via ssh. Without another user, you will be locked out">&2
echo "of this machine.">&2
echo>&2
echo "Ensure that either the root password or sudo have been configured">&2
echo "Any errors, downtime, or other generally negative outcome is your">&2
echo "own responsibility.">&2
echo>&2
echo "The following changes will be made:">&2
echo "--Add the I2P Repositories">&2
echo "--Update the system's packages">&2
echo "--Install I2P, Fail2ban, UFW, Lynx">&2
echo "--Change the SSH port to $sshport">&2
echo "--Disable Root Login">&2
echo "--Configure I2P to automatically start at boot">&2
echo "--Start I2P">&2
echo "--Configure Firewall to Only Allow I2P and SSH">&2
echo "--Enable Fail2ban and SSH">&2
echo "--Enable AppArmor">&2
echo
echo -n "Are you sure you wish to continue? (y/n)  "
read ans
case $ans in
    y*|Y*|t*|T*)
        # The user /probably/ wants to continue...
        ;;
    *)
        exit 0
        ;;
esac

#Edit Repos, Update System
cat  > /etc/apt/sources.list.d/i2p.list << EOF
deb http://deb.i2p2.no/ stable main
#deb-src http://deb.i2p2.no/ stable main
EOF

# Add the I2P repo key if apt doesn't know about it yet
if ! apt-key fingerprint | fgrep -q "7840 E761 0F28 B904 7535  49D7 67EC E560 5BCF 1346" > /dev/null 2>&1; then
    if wget --quiet https://geti2p.net/_static/i2p-debian-repo.key.asc -O $TMPFILE; then
        apt-key add $TMPFILE
        rm -f $TMPFILE
    else
        # Since fetching with wget failed, let's try getting it from a keyserver
        apt-key adv --keyserver hkp://pool.sks-keyservers.net --recv-key 0x67ECE5605BCF1346
    fi
fi

apt-get update
# preseed debconf to set I2P to start at boot
echo "i2p i2p/daemon boolean true" | debconf-set-selections

# The 'i2psvc' user is created by the 'i2p' package and is set
# to start I2P by default. You can set another user here but you
# must ensure that it exists, e.g.
#if ! getent passwd i2p; then
#    adduser --system --quiet --group --home /home/i2p i2p > /dev/null 2>&1
#fi
echo "i2p i2p/user string i2psvc" | debconf-set-selections
apt-get --yes upgrade && \
apt-get --yes install \
	pparmor \
	apparmor-profiles \
	apparmor-utils \
	fail2ban \
	i2p \
	i2p-keyring \
	lynx \
	ufw 


#Configure SSH
if [ -e /etc/ssh/sshd_config.backup ]; then
    echo "SSH already configured during a previous run."
else
    sed -i.backup -e "s/^\(Port\).*/\1 $sshport/;s/^\(PermitRootLogin\).*/\1 no/" /etc/ssh/sshd_config
fi

# If we end up here, I2P should be installed, running, and configured to start at boot.
# ..but let's make sure.
if service i2p status > /dev/null 2>&1; then :; else
    # Since we're here, I2P was not running. We'll make sure the initscript is enabled,
    # then start I2P
    sed -i.bak -e 's/^.*\(RUN_DAEMON\).*/\1="true"/' /etc/default/i2p
    service i2p start
fi

# Get the configured user from the debconf db
I2PUSER=$(debconf-show i2p |sed -e '/i2p\/user/!d' -e 's/.*:\s\+//')

if [ $I2PUSER != 'i2psvc' ]; then
    I2PHOME=$(getent passwd $I2PUSER | awk -F: '{print $6}')
else
    I2PHOME="/var/lib/i2p/i2p-config"
fi

#Check to ensure config file has generated before setting firewall rules
# Wait up to 10 seconds for router.config to be created.
wait_until 10 "test -e /var/lib/i2p/i2p-config/router.config"
i2pport=$(awk -F= '/i2np\.udp\.port/{print $2}' $I2PHOME/router.config)

if [ x$i2pport = 'x' ]; then
    echo "Error determining I2P's UDP port" >&2
    exit 1
else
    echo "The I2P port is $i2pport"
fi

#Set firewall rules to allow SSH and I2P
ufw default deny
ufw allow $sshport
ufw allow $i2pport

#Reload Fail2ban and SSH
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
/etc/init.d/fail2ban restart
/etc/init.d/ssh reload

#Enable Firewall
echo "Done! The firewall is about to be activated. The next time that you" >&2
echo "connect via ssh, you will need to use port $sshoprt on a non-root user." >&2
sleep 5
ufw enable
echo

#Enable AppArmor
aa-enforce /etc/apparmor.d/usr.bin.i2prouter
aa-enforce /etc/apparmor.d/usr.sbin.sshd

#Open Lynx For Bandwidth Configuration
echo "Lynx will open so that I2P's bandwidth settings can be configured." >&2
echo '(385KBps will be about 1TB per month)' >&2
echo -n "Press y when ready: "
read ans
case $ans in
    y*|Y*|t*|T*)
        lynx -accept_all_cookies http://127.0.0.1:7657/config
        ;;
    *)
        exit 0
        ;;
esac

# TODO: https://wiki.debian.org/AppArmor/HowToUse suggests this for install, but does this make sense on a VPS?
#mkdir /etc/default/grub.d
#echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=1 security=apparmor"' \ | sudo tee /etc/default/grub.d/apparmor.cfg
#update-grub
#reboot
