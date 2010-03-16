#!/bin/sh

. common.sh
check_cookie
read_args

#debug

if test "$Submit" = "country"; then
    echo "$(httpd -d $tz)" > /etc/TZ
	echo "$(httpd -d $timezone)" > /etc/timezone

elif test "$Submit" = "manual"; then
    hour=$(httpd -d $hour)
    date -s "$date $hour"

elif test "$Submit" = "ntpserver"; then
        sntp -P no -r $ntps
fi

hwclock -w -u

#enddebug
gotopage /cgi-bin/time.cgi

