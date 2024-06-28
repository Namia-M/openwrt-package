#!/bin/sh
# Wiwiz HotSpot Builder Utility
# Copyright wiwiz.com. All rights reserved.

CMD=$1
MAC=$2

COMMENT='auto generated by wiwiz'
TMPFILE='/tmp/hsbuilder_setspeed.tmp'
LOGFILE='/tmp/hsbuilder.log'

LANDEV=$(uci get wiwiz.portal.lan 2>/dev/null)
if [ "$LANDEV" == "" ]; then
	LANDEV=br-lan
fi

getIP() {
	_mac="$1"
	s=$(cat /proc/net/arp | grep -i -F "$_mac" | grep -F '0x2' | grep -F "$LANDEV" | awk '{print $1}' | head -n 1)
	echo "$s"
}

getIP2() {
	_mac="$1"
	s=$(cat /proc/net/arp | grep -i -F "$_mac" | grep -F "$LANDEV" | awk '{print $1}' | head -n 1)
	echo "$s"
}

getUpDown() {
	HID=$(uci get wiwiz.portal.hotspotid 2>/dev/null)
	if [ "$HID" = "" ]; then
		echo "setspeed.sh: getUpDown() unable to get hotspot_id." >>$LOGFILE
		return
	fi
	
	AS_HOSTNAME_X=$(uci get wiwiz.portal.server 2>/dev/null)
	if [ "$AS_HOSTNAME_X" = "" ]; then
		echo "setspeed.sh: getUpDown() unable to get AS_HOSTNAME_X." >>$LOGFILE
		return
	fi
	
	URL="http://$AS_HOSTNAME_X/as/s/getspeed/?gw_id=$HID&mac=$MAC"
	rm -f "$TMPFILE" 2>/dev/null
	curl -m 10 -o "$TMPFILE" "$URL"
	cat "$TMPFILE"
	rm -f "$TMPFILE" 2>/dev/null	
}

if [ "$1" = "" ]; then
	echo "Usage:"
	echo "setspeed.sh clear"
	echo "setspeed.sh set MAC"
	echo "setspeed.sh unset MAC"
	exit 1
fi

GIVEUP=""
for i in `seq 0 30`; do
	LOCK=$(cat /tmp/wiwiz_setspeed.lock 2>/dev/null)
	if [ "$LOCK" = "1" ]; then
		echo "Locked, waiting..."
		wdctl sleep 50000
	else
		break
	fi
	if [ "$i" = "30" ]; then
		GIVEUP="1"
	fi	
done
if [ "$GIVEUP" = "1" ]; then
	echo "waited too long. giving up."
	exit 9
fi

echo '1'>/tmp/wiwiz_setspeed.lock

if [ "$1" = "clear" ]; then
	cnt=$(uci show eqos 2>/dev/null | grep '=device' | wc -l)
	if [ "$cnt" = "0" ]; then
		rm -f /tmp/wiwiz_setspeed.lock 2>/dev/null
		exit 0;
	fi
	let maxindex=$cnt-1
	I=0
	for i in `seq 0 $maxindex`
	do
		_comment=$(uci get eqos.@device[$I].comment 2>/dev/null)
		if [ "$_comment" = "$COMMENT" ]; then
			uci delete eqos.@device[$I]
			let I=$I-1
		fi
		let I=$I+1
	done
	uci commit eqos
	/etc/init.d/eqos stop; /etc/init.d/eqos start
	echo "SetSpeed: $(date) clear" >>$LOGFILE
fi

if [ "$1" = "set" ]; then
	ip=$(getIP $MAC)
	
	if [ "$ip" = "" ]; then
		rm -f /tmp/wiwiz_setspeed.lock 2>/dev/null
		exit 2
	fi
	
	updown=$(getUpDown)
	# updown="speed 3 2"
	if [ "$updown" = "" ]; then
		rm -f /tmp/wiwiz_setspeed.lock 2>/dev/null
		exit 3
	fi
	
	if [ "$(echo $updown | grep speed)" = "" ]; then
		rm -f /tmp/wiwiz_setspeed.lock 2>/dev/null
		exit 4
	fi
	
	dl=$(echo "$updown" | cut -d ' ' -f 2)
	ul=$(echo "$updown" | cut -d ' ' -f 3)
	
	if [ "$dl" = "" -o "$ul" = "" ]; then
		echo "empty speed data"
		rm -f /tmp/wiwiz_setspeed.lock 2>/dev/null
		exit 0;
	fi
	
	cnt=$(uci show eqos 2>/dev/null | grep '=device' | wc -l)
	
	let maxindex=$cnt-1
	I=0
	for i in `seq 0 $maxindex`
	do
		_ip=$(uci get eqos.@device[$I].ip 2>/dev/null)
		if [ "$_ip" = "$ip" ]; then
			uci delete eqos.@device[$I]
			let I=$I-1
		fi
		let I=$I+1
	done
	
	uci add eqos device
	uci set eqos.@device[-1].ip="$ip"
	uci set eqos.@device[-1].download="$dl"
	uci set eqos.@device[-1].upload="$ul"
	uci set eqos.@device[-1].comment="$COMMENT"
	
	uci set eqos.@eqos[0].enabled='1'
	
	uci commit eqos
	/etc/init.d/eqos stop; /etc/init.d/eqos start
	echo "SetSpeed: $(date) set $MAC" >>$LOGFILE
fi

if [ "$1" = "unset" ]; then
	ip=$(getIP2 $MAC)
	if [ "$ip" = "" ]; then
		rm -f /tmp/wiwiz_setspeed.lock 2>/dev/null
		exit 5
	fi
	
	cnt=$(uci show eqos 2>/dev/null | grep '=device' | wc -l)

	let maxindex=$cnt-1
	I=0
	for i in `seq 0 $maxindex`
	do
		_ip=$(uci get eqos.@device[$I].ip 2>/dev/null)
		_comment=$(uci get eqos.@device[$I].comment 2>/dev/null)
		if [ "$_ip" = "$ip" -a "$_comment" = "$COMMENT" ]; then
			uci delete eqos.@device[$I]
			uci commit eqos
			let I=$I-1
		fi
		let I=$I+1
	done
	/etc/init.d/eqos stop; /etc/init.d/eqos start

	if [ "$MAC" != "" ]; then
		/usr/local/hsbuilder/kickmac.sh add $MAC
	fi

	echo "SetSpeed: $(date) unset $MAC" >>$LOGFILE
fi

rm -f /tmp/wiwiz_setspeed.lock 2>/dev/null
