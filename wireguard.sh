# Took from https://www.linksysinfo.org/index.php?threads/wireguard-on-freshtomato.76295/page-3
# Basic script to bring up a new Wireguard interface enabled to forward all incoming trrafic to internet/default route
# FreshTomato firmware for Netgear R700 (and others) has some bug related to CFT, so its disabled, build 2021.7
# If you are behind your ISP router, still need  to allow and forward incoming traffic to this host 
# Script assume you already have your private key on $HOME
# Wireguard working example https://www.youtube.com/watch?v=bVKNSf1p1d0
# Iptables good explanation https://www.youtube.com/watch?v=UvniZs8q3eU
# FreshTomato wiki https://wiki.freshtomato.org/doku.php/about

#!/bin/sh
NAME=wg0
PORT=51820
LOCKFILE=/var/run/wireguard-$NAME.lock
WGIP=10.10.10.1/24
WGMASK=10.10.10.0/24
WGPOSTROUTE=0.0.0.0/0
WGPOSTROUTEBR=`ip route | grep default | sed s/.*dev\ //g | sed s/\ .*//g`

#check if the wg-up script is already running
if [ -f $LOCKFILE ]; then
    logger "Wireguard-$NAME script already running"
    echo "Wireguard-$NAME script already running"
    exit 1
else
   touch $LOCKFILE
fi


# stop it if it is already running
wg show $NAME > /dev/null 2> /dev/null
if [ $? -eq 0 ]; then
    echo "Stopping existing $NAME wireguard instance." 1>&2
    ip link delete dev $NAME
    iptables -w 2 -D FORWARD -i $NAME -j ACCEPT 2> /dev/null
    iptables -w 2 -D FORWARD -o $NAME -j ACCEPT 2> /dev/null
    iptables -w 2 -t nat -D POSTROUTING -s $WGMASK -d $WGPOSTROUTE -o $WGPOSTROUTEBR -j MASQUERADE 2> /dev/null
    iptables -w 2 -D INPUT -s $WGMASK -i $NAME -j ACCEPT 2> /dev/null
    iptables -w 2 -D INPUT -p udp --dport $PORT -j ACCEPT 2> /dev/null
    logger "Wireguard-$NAME stopped"
else
    echo "Wireguard-$NAME not already running"
fi

if lsmod | grep wireguard &> /dev/null ; then
    echo "Wireguard module already loaded"
else
    echo "Wireguard module not loaded. Loading..."
    logger "Loading wireguard Kernel Module"
    modprobe wireguard
fi

ip link add dev $NAME type wireguard

# create the IP address for this server peer
ip -4 address add dev $NAME $WGIP

#Wireguard basic configuration
wg set $NAME  listen-port $PORT
wg set $NAME  private-key $HOME/private

while ! ip link set up dev $NAME
    do echo "ip link setup failed, will try again in 2 seconds..."
    logger "failed to setup ip link for $NAME, will try again in 2 seconds..."
    sleep 2
done

# iptables rules needed because default action is DROP
iptables -w 2 -C FORWARD -i $NAME -j ACCEPT 2> /dev/null || iptables -w 2 -A FORWARD -i $NAME -j ACCEPT
iptables -w 2 -C FORWARD -o $NAME -j ACCEPT 2> /dev/null || iptables -w 2 -A FORWARD -o $NAME -j ACCEPT

#allow incoming port on external firewall
iptables -w 2 -C INPUT -p udp --dport $PORT -j ACCEPT 2> /dev/null || iptables -w 2 -A INPUT -p udp --dport $PORT -j ACCEPT

# dst-nat rules for each destination subnet that the peer should be able to connect with
iptables -w 2 -t nat -C POSTROUTING -s $WGMASK -d $WGPOSTROUTE -o $WGPOSTROUTEBR -j MASQUERADE 2> /dev/null || \
iptables -w 2 -t nat -A POSTROUTING -s $WGMASK -d $WGPOSTROUTE -o $WGPOSTROUTEBR -j MASQUERADE

# input rules for each destination subnet that the peer should be able to connect with
iptables -w 2 -C INPUT -s $WGMASK -i $NAME -j ACCEPT 2> /dev/null || iptables -w 2 -A INPUT -s $WGMASK -i $NAME -j ACCEPT

# disable CTF 
iptables -t mangle -I PREROUTING -i $NAME -j MARK --set-mark 0x01/0x7 && logger "CTF disabled for $NAME"

logger "Wireguard-$NAME initialized"
rm $LOCKFILE


