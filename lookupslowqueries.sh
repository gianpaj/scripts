#!/bin/bash
#
# This script looks for slow queries in specific log files.
#
# The script outputs the analysis to /var/tmp/slowqueries.out unless specified otherwise on the cli.
# Declaring some variables.

# set -x -e

USAGE="Usage: $(basename $0) [-h] [-i arg] [-o arg])"
VERSION="0.1"

# Checking that the script is run with an option
if [ $# -eq 0 ]
then
    echo -e "$USAGE\n";
    echo -e "Please run with a valid option! Help is printed with '-h'."
    exit $E_OPTERROR;
fi

#
# Defining functions
#
nice_output ()
{
echo "-------------------------------------------------------------------------------------------------" > $outFile
printf "| %-15s | %-22s | %-100s |\n" "QUERY TIME" "DATE" "SLOW QUERY" >> $outFile
echo "|-----------------+-------------------------+------------+------------+------------+------------|" >> $outFile
}

#
# Function to check for slow queries.
#
check_slow ()
{
awk '/[0-9]{3,}ms$/ {print $NF "\t" $0}' $inFile | sed -e 's/[0-9]\{3,\}ms$//' | sed -e 's/\[conn[0-9]] //' | sort -rn >> $outFile
}

# Start-up Options

while getopts hvi:o: OPT
do
    case "$OPT" in
        h)
            echo -e "$USAGE\n";
            echo -e "-h:  Help";
            # echo -e "-v:  Version Information.\n";
            exit 0;
        ;;
        v)
            echo -e "\nVersion 0.1 of $(basename $0)\n";
            exit 0;
        ;;
        i)
            inFile=$OPTARG;
            echo "$inFile";
            [ OPTIND=${OPTIND} ];
            echo $OPTIND;
        ;;
        o)
            outFile=$OPTARG;
            echo "$outFile";
            [ OPTIND=${OPTIND} ];
            echo $OPTIND;
        ;;
        \?) echo $USAGE;
            exit 1;
            ;;
        *)  echo -e "\nOption -$OPTARG requires an argument.\n";
            exit 1;
    esac
done