#!/bin/bash
#
#	This script is used to generate a "Master" sequence that will play a number
#	of sequences specified on the command line.
#	Given a range of numbers for the sequences, e.g. 11 - 14, the script will
#	try to get the lengths of these sequences from each of the "host" robots databases
#	Using the results, it will determine the longest length for each sequence.
#	When the lengths are obtained, it will then build a Master sequence with
#	events to play the sequences on the "slave" robots by placing the events
#	at the times calculated by using the lengths for each sequence...
#
#	Currently can only generate master sequences from a range.
#	Would be nice to:
#	1.	Specify a list of sequences instead of a range.
#	2.	Generate sequences that "play" from the 2nd, 3rd, 4th sequence to the end...
#	3.	Add an overwrite option so that we don't delete existing masters?
#	4.	Something important - I forgot
#

usage()
{
cat << EOF
usage: $0 [-h] [-d] [-v] [-n] master-sequence first-sequence last-sequence

e.g.

$0 -v 9999 11 14

This script will generate a master sequence given the numbers of:
the master sequence, the first slave and the last slave to play.
the above example will generate a master sequence 9999 that plays sequences 11-14 inclusive
use -n to change the meaning of last-sequence to be the number of sequences to include, e.g.

$0 -v -n 9999 11 4
is the same as above.

OPTIONS:
   -t  test overlap!
   -h	Show this message
   -d	debug
   -v	Verbose
   -n	The third argument value specifies how many sequences are in a range (including the first sequence)
	rather than specifying the last sequence number
EOF
}

DEBUG=0
VERBOSE=0
RANGE=1
TEST_OVERLAP=0

while getopts "hdvnt" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         d)
             DEBUG=1
             ;;
         v)
             VERBOSE=1
             ;;
         n)
	      RANGE=0
	      ;;
	  t)
             TEST_OVERLAP=1
             ;;
         ?)
             usage
             exit
             ;;
     esac
done
shift $(($OPTIND - 1))

#Our Variables.
MASTER_SEQ=0
START_SEQ=
END_SEQ=

#Now parse the remaining arguments into variables
if [ -n "$1" ]; then
	MASTER_SEQ=$1
else
	usage
	exit
fi
if [ -n "$2" ]; then
	START_SEQ=$2
else
	usage
	exit
fi
if [ -n "$3" ]; then
	if [ 0 = ${RANGE} ]; then
		let "END_SEQ=${START_SEQ} -1 + ${3}"
	else
		END_SEQ=$3
	fi
else
	usage
	exit
fi


if [[ 1 = ${VERBOSE} ]];	then
	echo "$0 Running with values: MASTER_SEQ ${MASTER_SEQ}, START_SEQ ${START_SEQ}, END_SEQ ${END_SEQ}"
fi


#The IP addresses of the robots in the theatre - we need to talk to their databases.
#Lan setup
#hosts=("192.168.0.10" "192.168.0.12" "192.168.0.64" "192.168.0.49" "192.168.0.3")
#VPN setup with Router
hosts=("192.168.1.2" "192.168.1.3" "192.168.1.4" "192.168.1.5" "192.168.1.6")
PLAYERS=(1 5 6 7 8)

USER=user
PASS=password
DB=anim_data

declare -a SEQ_LENGTHS

for i in $( seq ${START_SEQ} ${END_SEQ} );
do
	SEQ_LENGTHS[${i}]=0
done

#This would be where we could use a "list" of sequences instead of a
#range - so our SQL would be something like "IN ($2,$3,$4...)"
SEQS="BETWEEN ${START_SEQ} and ${END_SEQ}"

SQL1="SELECT MAX(events.time) FROM events LEFT JOIN sequences seq ON events.sequence_id=seq.id
WHERE seq.sequence_number ${SEQS} GROUP BY seq.id ORDER BY seq.sequence_number ASC;"

for host in ${hosts[@]};
do
	if [[ 1 = ${VERBOSE} ]]; then
		echo "checking lengths on ${host}"
	fi
	if [[ 1 = ${DEBUG} ]]; then
		echo "CMD: mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e \"${SQL1}\""
	fi
	results=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL1}"`
	if [[ 1 = ${DEBUG} ]];	then
		echo "results ${results}"
	fi
	seq=${START_SEQ}
	for row in ${results[@]};
	do
		if [[ 1 = ${DEBUG} ]]; then
			echo "Sequence ${seq} length is ${row}"
		fi
		if [[ "${row}" -gt "${SEQ_LENGTHS[${seq}]}" ]]; then
			if [[ 1 = ${DEBUG} ]]; then
				echo "${row} is bigger than current ${SEQ_LENGTHS[${seq}]} for ${seq}"
			fi
			SEQ_LENGTHS[${seq}]=${row}
		fi
		let "seq += 1"
	done
done
if [[ 1 = ${VERBOSE} ]];	then
	echo "Found sequence lengths: ${SEQ_LENGTHS[*]}"
fi

#Now we need to build a master sequence

#Run the queries on the master box
host=${hosts[0]}

#SQL Queries
SQL_CREATE_SEQ="INSERT INTO sequences SET sequence_number=${MASTER_SEQ}, name='Master for ${START_SEQ} - ${END_SEQ}', description='Script Generated Master', type=1;"
SQL_GET_SEQ_ID="SELECT id FROM sequences WHERE sequence_number=${MASTER_SEQ};"
SQL_DEL_EVENTS="DELETE ev.* FROM events ev LEFT JOIN sequences seq ON ev.sequence_id=seq.id WHERE seq.sequence_number=${MASTER_SEQ};"
SQL_DEL_SEQ_OUTPUTS="DELETE op.* FROM sequence_outputs op LEFT JOIN sequences seq ON op.sequence_id=seq.id WHERE seq.sequence_number=${MASTER_SEQ};"



#Check if the master sequence exists if not, create it.
if [[ 1 = ${DEBUG} ]]; then
	echo "CMD: mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e \"${SQL_GET_SEQ_ID}\""
fi
SEQ_ID=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_GET_SEQ_ID}"`

if [[ 1 = ${DEBUG} ]]; then
 echo "First check for SEQ_ID: ${SEQ_ID}"
fi


if [  -z "${SEQ_ID=/ /}" ]; then
	if [[ 1 = ${VERBOSE} ]]; then
		echo "No sequence with number ${MASTER_SEQ} will create?"
	fi
	if [[ 1 = ${DEBUG} ]]; then
		echo "CMD: mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e \"${SQL_CREATE_SEQ}\""
	fi
	error=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_CREATE_SEQ}"`
	if [ -n "${error/ /}" ]; then
		echo "error ${error} with insert ${SQL_CREATE_SEQ}"
	fi
else

	#Delete the master's events - do we check here???
	if [[ 1 = ${VERBOSE} ]]; then
		echo "Sequence id ${SEQ_ID} exists for number ${MASTER_SEQ} will delete old events"
	fi
	if [[ 1 = ${DEBUG} ]]; then
		echo "CMD: mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e \"${SQL_DEL_EVENTS}\""
	fi
	results=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_DEL_EVENTS}"`
	if [[ 1 = ${DEBUG} ]]; then
		echo "results ${results}"
	fi

	#Delete the master's sequence outputs...
	if [[ 1 = ${DEBUG} ]]; then
		echo "CMD: mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e \"${SQL_DEL_SEQ_OUTPUTS}\""
	fi
	results=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_DEL_SEQ_OUTPUTS}"`
	if [[ 1 = ${DEBUG} ]]; then
		echo "results ${results}"
	fi
	#Update the master's "Name" column
	SQL_UPDATE_SEQ="UPDATE sequences SET name='Master for ${START_SEQ} - ${END_SEQ}', description='Script Generated Master', type=1 WHERE id=${SEQ_ID};"
	if [[ 1 = ${DEBUG} ]]; then
		echo "CMD: mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e \"${SQL_UPDATE_SEQ}\""
	fi
	results=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_UPDATE_SEQ}"`
	if [[ 1 = ${DEBUG} ]]; then
		echo "results ${results}"
	fi
fi

SEQ_ID=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_GET_SEQ_ID}"`
if [[ 1 = ${DEBUG} ]]; then
	echo "Second check for SEQ_ID ${SEQ_ID}"
fi


#If we don't have a master, we can't really carry on!
if [  -z "${SEQ_ID=/ /}" ]; then
	echo "Could not find or create a master sequence - cannot continue!"
	exit
fi

#Set up the default stuff for our sequence.
OUTPUT_NUMBER=65000
START_POS=0
GAP=200000

COUNT=0
TOTAL=0
#Now insert markers for playing each sequence on the slaves
for i in $( seq ${START_SEQ} ${END_SEQ} );
do
	if [[ 1 = ${VERBOSE} ]]; then
		echo "Will start sequence ${i} at ${START_POS}"
	fi
	for plyr in ${PLAYERS[@]};
	do
		ev=${i},0,0,1,${plyr}

		SQL_INSERT="INSERT INTO events SET sequence_id=${SEQ_ID}, time=${START_POS}, output_number=${OUTPUT_NUMBER}, value=\"${ev}\";"
		if [[ 1 = ${DEBUG} ]]; then
			echo "Insert Command ${SQL_INSERT}"
		fi
		error=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_INSERT}"`
		if [ -n "${error/ /}" ]; then
			echo "error ${error} with insert ${SQL_INSERT}"
		else
			let "COUNT+=1"
		fi
		let "TOTAL+=1"
	done
       if [[ 1 = ${TEST_OVERLAP} ]]; then
		let "START_POS = START_POS + (${SEQ_LENGTHS[${i}]} / 8) + GAP"
	else
		let "START_POS = START_POS + ${SEQ_LENGTHS[${i}]} + GAP"
	fi
done
#Add on a bit to the end of the sequence to allow for it to finish doing stuff?
let "START_POS = START_POS + GAP"

#Update the master's "duration" with the length of the whole lot!
SQL_UPDATE_DUR="UPDATE sequences SET play_length=${START_POS} WHERE id=${SEQ_ID};"
if [[ 1 = ${DEBUG} ]]; then
	echo "CMD: mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e \"${SQL_UPDATE_DUR}\""
fi
results=`mysql -h ${host} -u ${USER} --password=${PASS} --skip-column-names ${DB} -e "${SQL_UPDATE_DUR}"`
if [[ 1 = ${DEBUG} ]]; then
	echo "results ${results}"
fi
echo "Finished creating master sequence, inserted ${COUNT} of ${TOTAL} events into sequence ${SEQ_ID} successfully"
