for REDIS_NAME in $REDIS_LIST
do
    if [[ "$REDIS_NAME" == *prod* ]]; then
        echo "Skip $REDIS_NAME"
        continue
    fi

    echo "Processing $REDIS_NAME ..."
    /bin/bash ./add_ip.sh "$REDIS_NAME"
done
