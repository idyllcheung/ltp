#!/bin/sh
# Copyright (c) 2009 IBM Corporation
# Copyright (c) 2018 Petr Vorel <pvorel@suse.cz>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it would be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Author: Mimi Zohar, zohar@ibm.vnet.ibm.com
#
# Test whether ToMToU and open_writer violations invalidatethe PCR and are logged.

TST_SETUP="setup"
TST_CNT=3
TST_NEEDS_DEVICE=1

. ima_setup.sh
. daemonlib.sh

setup()
{
	FILE="test.txt"
	IMA_VIOLATIONS="$SECURITYFS/ima/violations"
	LOG="/var/log/messages"

	if status_daemon auditd; then
		LOG="/var/log/audit/audit.log"
	fi
	[ -f "$LOG" ] || \
		tst_brk TBROK "log $LOG does not exist (bug in detection?)"
	tst_res TINFO "using log $LOG"
}

open_file_read()
{
	exec 3< $FILE || exit 1
}

close_file_read()
{
	exec 3>&-
}

open_file_write()
{
	exec 4> $FILE || exit 1
	echo 'test writing' >&4
}

close_file_write()
{
	exec 4>&-
}

get_count()
{
	local search="$1"
	echo $(grep -c "${search}.*${FILE}" $LOG)
}

validate()
{
	local num_violations="$1"
	local count="$2"
	local search="$3"
	local max_attempt=3
	local count2 i num_violations_new

	for i in $(seq 1 $max_attempt); do
		read num_violations_new < $IMA_VIOLATIONS
		count2="$(get_count $search)"
		if [ $(($num_violations_new - $num_violations)) -gt 0 ]; then
			if [ $count2 -gt $count ]; then
				tst_res TPASS "$search violation added"
				return
			else
				tst_res TINFO "$search not found in $LOG ($i/$max_attempt attempt)..."
				tst_sleep 1s
			fi
		else
			tst_res TFAIL "$search violation not added"
			return
		fi
	done
	tst_res TFAIL "$search not found in $LOG"
}

test1()
{
	tst_res TINFO "verify open writers violation"

	local search="open_writers"
	local count num_violations

	read num_violations < $IMA_VIOLATIONS
	count="$(get_count $search)"

	open_file_write
	open_file_read
	close_file_read
	close_file_write

	validate $num_violations $count $search
}

test2()
{
	tst_res TINFO "verify ToMToU violation"

	local search="ToMToU"
	local count num_violations

	read num_violations < $IMA_VIOLATIONS
	count="$(get_count $search)"

	open_file_read
	open_file_write
	close_file_write
	close_file_read

	validate $num_violations $count $search
}

test3()
{
	tst_res TINFO "verify open_writers using mmapped files"

	local search="open_writers"
	local count num_violations

	read num_violations < $IMA_VIOLATIONS
	count="$(get_count $search)"

	echo 'testing testing' > $FILE

	ima_mmap -f $FILE &
	# wait for violations appear in logs
	tst_sleep 1s

	open_file_read
	close_file_read

	validate $num_violations $count $search

	# wait for ima_mmap to exit, so we can umount
	tst_sleep 2s
}

tst_run
