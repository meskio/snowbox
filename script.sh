#!/bin/sh
# POSIX

build=0
client=0

while :; do
    case $1 in
        -b|-\?|--build)
            build=1
            ;;
        -c|-\?|--client)
            client=1
            ;;
        -?*)
            printf 'Warning: Unknown option: %s\n' "$1" >&2
            ;;
        *) #default case: no more options
            break
    esac

    shift
done

# we manually copy files locally (avoiding go install so we don't have to recompile every time)

if [ "$build" -ne "0" ]; then
    #kill broker, proxy, client processes
    pkill -f broker
    pkill -f client

    cd snowflake.git/broker

    go get -d -v
    go build -v

    cd ../proxy-go
    go get -d -v
    go build -v

    cd ../client
    go get -d -v
    go build -v

    cd ../proxy
    npm run build
    #need to point to our localhost broker instead
    sed -i 's/snowflake-broker.freehaven.net/localhost:8080/' build/embed.js
    
    cd /go/src
fi

if [ "$client" -eq "0" ]; then
    cp snowflake.git/broker/broker /go/bin/
    cp snowflake.git/proxy-go/proxy-go /go/bin/
    cp snowflake.git/client/client /go/bin/
    cp snowflake.git/client/torrc-localhost /go/bin

    cd /go/bin

    broker -addr ":8080" -disable-tls > broker.log 2> broker.err &
    proxy-go -broker "http://localhost:8080" > proxy.log 2> proxy.err &
else
    cd /go/bin

    # Find a SOCKSPort to bind to that is not in use
    count=0
    while :; do
        if ! netstat --inet -n -a -p 2> /dev/null | grep ":$(($count+9050))" ; then
            break
        fi
        count=$(($count+1))
    done

    cp torrc-localhost torrc-$count
    sed -i -e "s/datadir/datadir$count/g" torrc-$count
    sed -i -e "/^-url http:\/\/localhost:8080\//a -log snowflake_client-$count.log" torrc-$count
    echo "SOCKSPort $(($count+9050))" >> torrc-$count

    tor -f torrc-$count > client-$count.log 2> client-$count.err &
fi

# Start X and firefox for proxy
/usr/bin/Xvfb :1 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 2
/usr/bin/x11vnc -display :1.0 >/dev/null 2>&1 &

DISPLAY=:1 firefox file:/go/src/snowflake.git/proxy/build/embed.html &
