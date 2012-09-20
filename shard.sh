#!/bin/bash

# Small shell script to set up sharded MongoDB server.
# Currently this script assumes that you have mongod and mongos installed, I know it's a little pre-sumptious but hey :)
# The script then starts a sharded cluster from scratch (all elements),shards a database, pulls down json data from the Interwebs and imports it into a collection in a database and in turn shards that collection.

# This script runs in interactive mode by default.

# TO DO: Improve error handling
# TO DO: Include a "-h" & "-y" options at least - i.e. include some positional parameters to differentiate with interactive mode.
# TO DO: More clever around "sleeping"
# TO DO: Tidy up index creation and sharding section.

set -e

# Declaring the USAGE variable

USAGE="Usage: `basename $0` [-fhiv] [-b arg] [-m arg] [-o arg] args. To run interactively, you need to run with the "-i" option. You will be prompted for various options around mongod, mongos, data file location and importing the data. To force the answer to be 'yes' for everything, i.e. do NOT run interactively run with '-f'. It is compulsory to run with either '-i' or '-f'."

# Checking that the script is run with an option
if [ $# -eq 0 ]
then
    echo -e "\nPlease run with a valid option! Help is printed with '-h'."
    echo -e "\n$USAGE\n";
    exit $E_OPTERROR;
fi

# Parse command line options.
while getopts fhivb:m:o: OPT
do
    case "$OPT" in
        f)
            byebye="y"
            remove="y"
            answer_d="y"
            answer_s="y"
            import="y"
        ;;
        h)
            echo -e "\n$USAGE\n";
            echo "-b: Forcibly answer yes for everything but reference a bsondump file as an argument.";
            echo "-f: Forcibly answer yes for everything. Dynamically imports a json file created from retrieving Twitter hashtags.";
            echo "-h: Help";
            echo "-i: Run in interactive mode. One of '-f' or '-i' are compulsory."
            echo "-m: Forcibly answer yes for everything but reference a json file as an argument.";
            echo "-o: Output to file (requires an argument)";
            echo "-v: Version Information.";
            echo -e "\nAll other options are currently invalid.\n";
            exit 0;
        ;;
        i) # The interactive questions over and done with :) Putting them all together to enable a "force-yes" option, there must be a cleaner way though.
            echo -e "As we're testing, is it ok to kill any mongod and mongos processes that may be running (y/n)?\n";
            read byebye
            echo -e "\nHave you previously run this script and want to remove your original data (y/n)? Entering 'y' means that all previous sharding and config data will be removed.\n"
            read remove
            echo -e "\nIs mongod @ $(which mongod) (y/n)?\n"
            read answer_d
            echo -e "Is mongos @ $(which mongos) (y/n)?\n"
            read answer_s
            echo -e "\n To allow the script perform its default action and import data from the Interwebs, enter 'y'.\n To import your own json data via 'mongoimport', enter 'j'.\n To import a bson dump with mongorestore, enter 'b'.\n";
            read import
        ;;
        b)
            byebye="y"
            remove="y"
            answer_d="y"
            answer_s="y"
            import="b"
        ;;
        m)
            byebye="y"
            remove="y"
            answer_d="y"
            answer_s="y"
            import="m"
        ;;
        v)
            echo "`basename $0` version 0.3"
            exit 0;
        ;;
        o) OUTPUT_FILE=$OPTARG
        ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2;
            echo $USAGE 1>&2
            exit 1;
        ;;
        :)
            echo "The option -$OPTARG must have an argument." 1>&2
            exit 1
        ;;
    esac
done

# Some basic checking to see if MongoD is installed.

which mongod
if [ ! $? -eq 0 ]
then
    which apt-get
    [ $? -eq 0 ] && echo -e "\nYou seem to be running a Ubuntu distro, please go to http://docs.mongodb.org/manual/tutorial/install-mongodb-on-debian-or-ubuntu-linux/ for further information on installing MongoDB for Ubuntu.\n" && exit 1;
    which yum
    [ $? -eq 0 ] && echo -e "\nYou seem to be running a Red Hat distro, please go to http://docs.mongodb.org/manual/tutorial/install-mongodb-on-redhat-centos-or-fedora-linux/ for further information on installing MongoDB for Red Hat.\n" && exit 1;
    uname -a | grep Darwin
    [ $? -eq 0 ] && echo -e "\nYou seem to be running on OSX, please go to http://docs.mongodb.org/manual/tutorial/install-mongodb-on-os-x/ for further information on installing MongoDB for Mac OS.\n" && exit 1;
fi

if [ $(ps auwx | awk '/mongod/ {print $11}' | grep -vc awk) -gt 0 ]
then
    echo -e "\nThere are currently some mongo(d|s) processes running!!!!\n";
    case "$byebye" in
        y|Y) killall mongod mongos
            ;;
        n|N) echo -e "\nMoving on, not killing anything.....\n"
            ;;
        *) echo -e "\nPlease enter one of 'y', 'Y', 'n' or 'N'. Now exiting, bye bye!\n"
            exit 10;
            ;;
    esac
else
echo -e "\nNo mongo(d|s) process currently running!\n"
fi

# Setting some variables. As this is only testing, we'll create the data directories under the home directory. This will also ensure that we don't have to worry about permissions issues.

d_dirs="
$HOME/data/db/00
$HOME/data/db/01
$HOME/data/db/02
"

cdir="$HOME/data/db/config"
ldir="/var/tmp/shard"

all_dirs="
$cdir
$ldir
$d_dirs
"
twitter_json="/var/tmp/twitter.json" # JSON file for the data input to create the sharded collection

del="rm -rf"

# Additional parameters for both mongod and mongos
#MONGOD_PARAMS="--nojournal --noprealloc" # These options make MongoD quicker to load, NEVER run without a journal in production btw!!!
MONGOD_PARAMS="--noprealloc"
MONGOS_PARAMS=""

for all in $all_dirs
do
  [ ! -d $all ] && mkdir -p $all # Ensuring all required directories are created.
done

# Here we remove or keep the shard data based on the value of the $remove variable.
case "$remove" in
    y|Y) [ -d $all ] && $del $all/* && echo -e "\nRemoving old sharding & config data.\n" # If they are created, removing the redundant data so we have a clean start.
    ;;
    n|N) [ -d $all ] && echo -e "\nKeeping the old sharding and config data. Hopefully you're not going to import data that's already there.\n"
    ;;
    *) echo -e "\nPlease enter 'y' or 'n', nothing-else (case-insensitive). Now exiting, bye bye!\n";
    exit 11;
    ;;
esac

# Using Twitter hashtags to pull down data in json format.

hashtags="
news
christmas
xmas
olympics
jobs
business
football
FF
FollowFriday
security
soccer
epl
premiership
nba
nfl
mlb
nhl
laliga
news
cloud
ladygaga
bigdata
xfactor
london
newyork
sanfrancisco
google
apple
iphone
android
twitter
facebook
fb
music
"

s_port="20000" # MongoS port

# Following code block defines mongod and mongos. Provides the ability to run different versions of mongod and mongos...woot!!!
# Defining the version of mongod, as per the $answer_d variable.

case "$answer_d" in
    y|Y) mongod=$(which mongod)
    ;;
    n|N) echo -e "What is the full path to mongod?\n"
    read mongod
    ;;
    *) echo -e "\nPlease enter 'y' or 'n', nothing-else (case-insensitive). Now exiting, bye bye!\n";
    exit 12;
esac

echo -e "\nmongod is at $mongod\n"

# Defining the version of mongos, as per the $answer_d variable.

case "$answer_s" in
    y|Y) mongos=$(which mongos)
    ;;
    n|N) echo -e "What is the full path to mongos?\n"
    read mongos
    ;;
    *) echo -e "\nPlease enter 'y' or 'n', nothing-else (case-insensitive). Now exiting, bye bye!\n";
    exit 13;
esac

echo -e "\nmongos is here at $mongos\n"

# mongod and mongos re now defined and so we now can start the various elements of the MongoDB sharding infrastructure.

for dir in $d_dirs
do
    port=$(echo $dir | awk -F/ '{print $NF}')
    if [ -d "$dir" ]
    then
        $mongod --shardsvr --dbpath $dir --port 100$port --fork --logpath $ldir/shard.$port.log $MONGOD_PARAMS # Start MongoDB Sharded Servers
        continue # Go to next iteration of $dir
    fi
    mkdir -p $dir
    $mongod --shardsvr --dbpath $dir --port 100$port --fork --logpath $ldir/shard.$port.log $MONGOD_PARAMS # Start MongoDB Sharded Servers, if directories don't exist
done

# Config Server & MongoS configuration (with a small chunk size of 1 MB.

$mongod --configsvr --dbpath $cdir --port $s_port --fork --logpath $ldir/configdb.log $MONGOD_PARAMS

echo -e "\n ==> Sleeping for 60 seconds after starting the config server...\n"
sleep 60 # Sleeping.....

# Ensuring that all 3 mongod shards have started up correctly!

if [ $(ps auwx | grep -c 'mongod --shardsvr'| grep -v grep) -lt 3 ]
then
    echo -e "There seems to be a problem starting some of the shards, please examine the debug information in the relevant shard.*.log file in $ldir.\n";
    echo -e "Now exiting!\n";
    exit 13;
elif [ $(ps auwx | grep -c 'mongod --configsvr'| grep -v grep) -lt 1 ]
then
    echo -e "There seems to be a problem starting the config server, please examine the debug information in the config server configdb.log file in $ldir.\n";
    echo -e "Now exiting!\n";
    exit 14;
else
    echo -e "\nIt looks like the three mongod shards and the config server have all started correctly. Wuhoo!\n";
fi

$mongos $MONGOS_PARAMS --configdb localhost:$s_port --chunkSize 1 --fork --logpath $ldir/mongos.log

echo -e "\n ==> Sleeping for 180 seconds after starting the mongos...\n";
sleep 180 # Sleeping.....

# Ensuring that the mongos has started up correctly!

if [ $(ps auwx | grep -c 'mongos'| grep -v grep) -lt 1 ]
then
    echo -e "There seems to be a problem starting the mongos, please examine the debug information in the mongos.log file in $ldir.\n";
    echo -e "Now exiting!\n";
    exit 15;
else
    echo -e "\nIt looks like the mongos has started correctly. Wuhoo!\n"
fi

# Configuring the shards - first adding the shards, then sharding the db and the collections. Unable to get the "addshard command to pick up localhost using a variable from a for loop."
echo -e "Invoking: db.RunCommand({addshard: ...})\n";
    mongo admin --eval 'db.runCommand( { addshard : "localhost:10000" } )'
    mongo admin --eval 'db.runCommand( { addshard : "localhost:10001" } )'
    mongo admin --eval 'db.runCommand( { addshard : "localhost:10002" } )'

# Checking the shards have been created successfully.

for dir in $d_dirs
do
    i=$(echo $dir | awk -F/ '{print $NF}')
    [ $(mongo admin --eval 'sh.status()' | grep -c :100$i) -eq 1 ] && echo -e "\nAdded shard on port 100$i.....\n"
done

# Enabling sharding & using Twitter to import some data into the mongos now.

mongo admin --eval 'db.runCommand( { enablesharding : "twitter" } )'
[ $(mongo admin --eval 'sh.status()' | egrep -c 'twitter.*part.*true') -eq 1 ] && echo -e "Successfully sharded Twitter DB, woot!\n"

# Importing data into the "tweets" collection in the twitter database. This can be dynamically with an Interet connection via Twitter or via a local file.
# The method of import depends on the setting of the $import variable.

case "$import" in
    y|Y) # Using the "real" Twitter to collate some data
        echo -e "\nChecking internet connectivity (http get to google.com)\n";
        curl -s -o /dev/null www.google.com 2>&1
        if [ $? -eq 0 ]
        then
            echo -e "\nInterweb connectivity looks good!\n";
            for coll in $hashtags
            do
                echo -e "\n Retrieving hashtag $coll.....\n";
                curl -s https://search.twitter.com/search.json?q=%23$coll >> $twitter_json # Used 'tee' initially but too much standard output.
                echo "" >> $twitter_json
            done
            mongoimport -d twitter -c tweets --file $twitter_json && echo -e "\nImporting the dynamically created twitter.json file.\n" # Importing the data retrieved from the Interweb.
            else
            echo -e "\nHTTP GET to google has failed. Please verify you have network connectivity and HTTP outbound is allowed. Surely, it is? It's only a test, not a production DB with real, production data, is it?\n"
            exit 16;
        fi
        ;;
    j|J) echo -e "\nPlease provide the filename (including the full path) of your json file to be imported.\n"
        read $import_file
        suffix=$(echo $import_file | awk -F. '{print $NF}')
        if [ $suffix = "json"]
        then
        mongoimport -d twitter -c tweets --file $import_file && echo -e "\nImporting $import_file. The database is called 'twitter' and the collection is 'tweets'."
        else
            echo -e ""\nPlease provide a valid json file for import. Now exiting, bye bye!\n";"
        exit 17;
        fi
        ;;
    b|B) echo -e "\nPlease provide the filename (including the full path) of your bson file to be imported.\n"
         read $import_file
         suffix=$(echo $import_file | awk -F. '{print $NF}')
         if [ $suffix = "bson"]
         then
             mongorestore --objcheck -d twitter -c tweets $import_file && echo -e "\nImporting $import_file. The database is called 'twitter' and the collection is 'tweets'."
         else
             echo -e ""\nPlease provide a valid bson file for import. Now exiting, bye bye!\n";"
             exit 18;
         fi
    ;;
    *) echo -e "\nPlease enter 's', 'j' or 'b', nothing-else (case-insensitive). Now exiting, bye bye!\n";
    exit 19;
    ;;
esac

# Creating an index so we subsequently create a shard key over it and then sharding the tweets collection.

    mongo twitter --eval 'db.tweets.ensureIndex({"query":1, "max_id":1})'
    mongo admin --eval 'db.runCommand( { shardcollection : "twitter.tweets", key : {"query": 1, "max_id": 1} } )'

# Tidy up - deleting the json file that we created from Twitter hashtags.
#$del $twitter_json
