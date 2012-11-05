#!/usr/bin/env python
#
# This script looks for slow queries in specific mongodb log files.
#
# The script outputs the analysis to /var/tmp/slowqueries.out
# unless specified otherwise on the cli.
# Declaring some variables.

import subprocess
import argparse

parser = argparse.ArgumentParser(
                    description='Look for slow queries in mongodb log files.')
parser.add_argument(nargs='?',
                    dest='inputlogfile',
                    help='a single mongodb log file')

args = parser.parse_args()
# print(args.inputlogfile)

outputlogfile = args.inputlogfile[:-4] + '_slow.log'
f = open(outputlogfile, 'w')

f.write("|" + "-" * 95 + "|\n")
f.write("| %s | %11s | %66s |\n" % ("QUERY TIME", "DATE", "SLOW QUERY"))
f.write("|-----------------+-------------------------+------------+------------+------------+------------|\n")
f.close()

# print "Hello World"
check = ("awk '/[0-9]{3,}ms$/ {print $NF \"\\t\" $0}' " + args.inputlogfile +
" | sed -e 's/[0-9]\{3,\}ms$//' | sed -e 's/\[conn[0-9]] //' | sort -rn >> " +
outputlogfile)

subprocess.call(check, shell=True)

print 'Written to:\n', outputlogfile
