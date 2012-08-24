#!/bin/bash

# Small shell script to set up sharded MongoDB server.
# Once this script is run, further configuration is required through the Mongo Shell - please see shard.txt.
# Currently this script assumes that you have mongod and mongos installed, I know it's a little pre-sumptious but hey :)
# Cleaning up by killing other mongod shardsvr processes.
set -e


# Check if there are mongod processes running.

if [ $(ps auwx | grep -c mongod | grep -v grep) -gt 1 ]
then
    echo -e "\nThere are currently some mongo(d|s) processes running!!!!\n"
    echo -e "As we're testing, is it ok to kill all mongod and mongos process (y/n)?\n"
    read byebye
    case "$byebye" in
        y|Y) killall mongod mongos
            ;;
        n|N) echo -e "Moving on, not killing anything.....\n"
            ;;
        *) echo -e "Please enter 'y' or 'n', nothing-else (case-insenstive). Now exiting!\n";
            exit 10;
            ;;
    esac
else
    echo -e "\nNo mongo(d|s) process currently running!\n"
fi
    
# Setting some variables.
# As this is only testing, we'll create the data directories under the home directory. This will also ensure that we don't have to worry about permissions issues.

d_dirs="
$HOME/data/db/11
$HOME/data/db/22
$HOME/data/db/33
"

cdir="$HOME/data/db/config"
ldir="/tmp/shard"

all_dirs="
$cdir
$ldir
$d_dirs
"

for all in $all_dirs
do
  [ ! -d $all ] && mkdir -p $all                                                        # Ensuring all required directories are created.
  [ -d $all ] && rm -rf $all/* && echo -e "Removing old sharding & config data.\n"      # If they are created, removing the redundant data so we have a clean start.
done

# I use Twitter hashtags to pull down data in json format.

hashtags="
olympics
jobs
premiership
"
s_port="20000" # MongoS port

# Asking where is mongod, as we may want to test a non-default version

echo -e "Is mongod @ $(which mongod) (y/n)?\n"
read answer_d

if [ "$answer_d" == "y" ]
then
    mongod=$(which mongod)
else
    echo -e "What is the full path to mongod?\n"
    read mongod
fi

echo -e "mongod is at $mongod\n"

# Asking where is mongos, as we may be testing a different version

echo -e "Is mongos @ $(which mongos) (y/n)?\n"
read answer_s

if [ "$answer_s" == "y" ]
then
    mongos=$(which mongos)
else
    echo -e "What is the full path to mongos?\n"
    read mongos
fi
echo -e "mongos is here at $mongos\n"

# This is where stuff happens.....

for dir in $d_dirs
do
    port=$(echo $dir | awk -F/ '{print $NF}')
    if [ -d "$dir" ]
        then
        $mongod --shardsvr --dbpath $dir --port 100$port --fork --logpath $ldir/shard.$port.log # Start MongoDB Sharded Servers
        continue # Go to next iteration of $dir
    fi
    mkdir -p $dir
    $mongod --shardsvr --dbpath $dir --port 100$port --fork --logpath $ldir/shard.$port.log # Start MongoDB Sharded Servers, if directories don't exist
done

# Config Server & MongoS configuration (with a small chunk size of 1 MB.

$mongod --configsvr --dbpath $cdir --port $s_port --fork --logpath $ldir/configdb.log

sleep 30 # Sleeping for 30 seconds......

# Ensuring that all mongods have started up correctly!

if [ $(ps auwx | grep -c 'mongod --shardsvr'| grep -v grep) -lt 3 ]
then
    echo -e "There seems to be a problem starting some of the shards, please examine the debug information in the relevant shard.*.log file in $ldir.\n"
    echo -e "Now exiting!\n"
    exit 11
elif [ $(ps auwx | grep -c 'mongod --configsvr'| grep -v grep) -lt 1 ]
then
    echo -e "There seems to be a problem starting the config server, please examine the debug information in the config server configdb.log file in $ldir.\n"
    echo -e "Now exiting!\n"
    exit 12
else
    echo -e "It looks like the three mongod shards and the config server have all started correctly. Wuhoo!\n"
fi

$mongos --configdb localhost:$s_port --chunkSize 1 --fork --logpath $ldir/mongos.log

sleep 180 # Sleeping for 3 minutes as everything has to be rebuilt due to all the data being removed.......

# Ensuring that the mongos has started up correctly!

if [ $(ps auwx | grep -c 'mongos'| grep -v grep) -lt 1 ]
then
    echo -e "There seems to be a problem starting the mongos, please examine the debug information in the mongos mongos.log file in $ldir.\n"
    echo -e "Now exiting!\n"
    exit 13
else
    echo -e "It looks like the mongos has started correctly. Wuhoo again!\n"
fi

# Configuring the shards - first adding the shards, then sharding the db and the collections

    mongo admin --eval 'db.runCommand( { addshard : "localhost:10011" } )'
    mongo admin --eval 'db.runCommand( { addshard : "localhost:10022" } )'
    mongo admin --eval 'db.runCommand( { addshard : "localhost:10033" } )'
    mongo admin --eval 'sh.status()'
for i in 11 22 33
do
    echo -e "Added shard on port 100$i.....\n"
done
    
# Enabling sharding & using Twitter to import some data into the mongos

sleep 5.....
mongo twitter --eval 'db.runCommand( { enablesharding : "twitter" } )'
echo -e "Sharded Twitter DB\n"

for coll in $hashtag
do
    echo -e "\n Sharding $coll\n"
    curl https://search.twitter.com/search.json?q=%23$coll | mongoimport -d twitter -c $coll
    mongo admin --eval 'db.runCommand( { shardcollection : "twitter.$coll", key : {name : 1} } )'
done