#!/bin/bash

# netfilter mark
NETFILTER_MARK=114514

# iproute2 rule table id
IPROUTE2_TABLE_ID=100

# Redir
FORWARD_PROXY_REDIRECT=7892

_setup(){
    ip route replace default dev utun table "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule del fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"  >> /dev/null 2>&1
    ip rule add fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID" >> /dev/null 2>&1
    nft flush ruleset
    nft -f - << EOF
    include "/lib/clash/private.nft"
    include "/lib/clash/chnroute.nft"

    table ip nat {
        chain PREROUTING {
            type nat hook prerouting priority -100; policy accept;
            ip protocol != { tcp, udp } accept;
            ip daddr \$private_list accept;
            ip daddr \$chnroute_list accept;
            meta l4proto tcp redirect to :$FORWARD_PROXY_REDIRECT
        }
    }
    table ip mangle {
        chain PREROUTING {
            type filter hook prerouting priority -150; policy accept;
            ip protocol != { tcp, udp } accept;
            ip daddr \$private_list accept;
            ip daddr \$chnroute_list accept;
            meta l4proto udp mark set $NETFILTER_MARK
        }
    }
EOF
    exit 0
}

_clean(){
    ip route del default dev utun table "$IPROUTE2_TABLE_ID"
    ip rule del fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"
    nft -f - << EOF
    flush table ip nat
    delete table ip nat
    flush table ip mangle
    delete table ip mangle
EOF
    exit 0
}

case "$1" in
"setup") _setup;;
"clean") _clean;;
esac
