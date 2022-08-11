#!/bin/bash

if [ "$EUID" -eq 0 ]; then
	echo "Please do not run with sudo."
	exit 1
fi

root="${0%/*}"
instances=$root/instances
src=$root/src
plugins=$src/plugins

declare -A Versions=( ["neo4j"]=4.1.1 ["neo4j_apoc"]=4.1.0.2 ["neo4j_gds"]=1.3.1 )
busy_ports=()

find_all_neo4j_instances_list()
{
	instances_list=()
	for instance in `ls "$instances"` ; do
		instances_list+=$(basename "$instance")
		instances_list+=";"
	done

	echo "${instances_list[@]}"
}

find_running_neo4j_instances_list()
{
	running_instances_list=()
	for instance in `ls "$instances"` ; do
		if instance_has_pid $(basename "$instance"); then
			running_instances_list+=$(basename "$instance")
			running_instances_list+=";"
		fi
	done

	echo "${running_instances_list[@]}"
}

find_all_busy_port()
{
	for instance in "$instances"/* ; do
		bolt_port=$(grep 'dbms.connector.bolt.listen_address=:*' $instance/conf/neo4j.conf | cut -d ":" -f2)
		busy_ports+=($bolt_port)

		http_port=$(grep 'dbms.connector.http.listen_address=:*' $instance/conf/neo4j.conf | cut -d ":" -f2)
		busy_ports+=($http_port)

		https_port=$(grep 'dbms.connector.https.listen_address=:*' $instance/conf/neo4j.conf | cut -d ":" -f2)
		busy_ports+=($https_port)
	done
}

new_port()
{
	while true ; do
		local port=$((1000 + RANDOM % 9000))

		if ! lsof -Pi :$port -t >/dev/null ; then
			if [[ ! " ${busy_ports[@]} " =~ " ${port} " ]]; then
			    echo $port
			    break
			fi
		fi
	done
}

initialize()
{
	mkdir -p $instances
	create_new_instance "default"
	start_neo4j_instances "default"
}

check_neo4j_response()
{
	name=$1
	port=$(grep 'dbms.connector.http.listen_address=:*' $instances/$name/conf/neo4j.conf | cut -d ":" -f2)	
	address="0.0.0.0:$port"

	end="$((SECONDS+700))"
	while true; do
	    [[ "200" = "$(curl --silent --write-out %{http_code} --output /dev/null $address)" ]] && break
	    [[ "${SECONDS}" -ge "${end}" ]] && return 1
	    sleep 1
	done
}

neo4j_initialize_password() {
	name=$1
	FILE=$instances/$name/data/dbms/auth
	if [ -f "$FILE" ]; then
		rm $FILE
	fi

	$instances/$name/bin/neo4j-admin set-initial-password a > /dev/null 2>&1 
	retVal=$?
	if [ $retVal -ne 0 ]; then
		echo "$name didn't create successfully"
		return 1
	fi
	echo "$name created"
}

create_new_instance()
{
	name=$1
	if [ ! -d $instances/$name ]; then
		tar -xf $src/neo4j-community-${Versions[neo4j]}-unix.tar.gz --directory $instances
		mv $instances/neo4j-community-${Versions[neo4j]} $instances/$name

		cp $plugins/apoc-${Versions[neo4j_apoc]}-core.jar $instances/$name/plugins
		cp $plugins/neo4j-graph-data-science-${Versions[neo4j_gds]}-standalone.jar -d $instances/$name/plugins

		sed -i '/#dbms.default_listen_address=0.0.0.0/c\dbms.default_listen_address=0.0.0.0' $instances/$name/conf/neo4j.conf
		sed -e '/dbms.directories.import=/ s/^#*/#/' -i $instances/$name/conf/neo4j.conf
		grep -qxF 'dbms.security.procedures.unrestricted=gds.*,apoc.*' $instances/$name/conf/neo4j.conf || echo 'dbms.security.procedures.unrestricted=gds.*,apoc.*' >> $instances/$name/conf/neo4j.conf

		neo4j_initialize_password $name
	else
		echo "$name already exists."
		return 1
	fi
}

config_neo4j_instances()
{
	name=$1
	find_all_busy_port

	bolt_port=$(new_port)
	busy_ports+=($bolt_port)
	sed -i 's/[#]*dbms.connector.bolt.listen_address=:[0-9]*\b/dbms.connector.bolt.listen_address=:'$bolt_port'/g' $instances/$name/conf/neo4j.conf

	http_port=$(new_port)
	busy_ports+=($http_port)
	sed -i 's/[#]*dbms.connector.http.listen_address=:[0-9]*\b/dbms.connector.http.listen_address=:'$http_port'/g' $instances/$name/conf/neo4j.conf

	https_port=$(new_port)
	busy_ports+=($https_port)
	sed -i 's/[#]*dbms.connector.https.listen_address=:[0-9]*\b/dbms.connector.https.listen_address=:'$https_port'/g' $instances/$name/conf/neo4j.conf

	echo "bolt port: $bolt_port"
	echo "http port: $http_port"
	echo "https port: $https_port"
}

start_neo4j_instances()
{	
	name=$1
	if ! instance_has_pid $name; then

		if [[ "$name" != "default" ]] ; then
			config_neo4j_instances $name  > /dev/null 2>&1 
		fi

		command $instances/$name/bin/neo4j start > /dev/null 2>&1 
		
		if [ $? -eq 0 ]; then
			check_neo4j_response $name
			if [ $? -eq 0 ]; then
				return 0
			else
				return 1
			fi
		else
			echo "$name didn't start successfully"
			return 1
		fi
	else
		echo "$name is already running"
	fi
}

stop_neo4j_instances()
{
	name=$1
	if instance_has_pid $name; then
		command $instances/$name/bin/neo4j stop > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "$name stopped"
		else
			echo "$name didn't stop successfully"
		fi
	else
		echo "$name is not running"
	fi
}

restart_neo4j_instances()
{
	name=$1
	command $instances/$name/bin/neo4j restart > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		check_neo4j_response $name
		echo "$name restarted"
	else
		echo "$name didn't restart successfully"
	fi
}

delete_neo4j_instances()
{	
	name=$1
	if [ ! -d "$instances/$name" ]; then
		echo "$name does not exist"
		return 1
	fi
	if instance_has_pid $name; then
		echo "first stop $name"
	else
		rm -rf $instances/$name
		if [ $? -eq 0 ]; then
			echo "$name deleted"
		else
			echo "$name didn't delete successfully"
		fi
	fi
}

state_neo4j_instances()
{
	name=$1
	if [ ! -d "$instances/$name" ]; then
		echo "NOT_EXIST"
		return 0
	fi
	port=$(grep 'dbms.connector.http.listen_address=:*' $instances/$name/conf/neo4j.conf | cut -d ":" -f2)	
	address="0.0.0.0:$port"

	if instance_has_pid $name; then
		response=$(curl -s -o /dev/null -w '%{http_code}' $address)
		if [ $response -eq 200 ]; then
			echo "RUNNING"
		else
			echo "SWITCHING"
		fi
	else
		echo "STOPPED"
	fi
}

find_neo4j_instance_bolt_port()
{
	name=$1
	if instance_has_pid $name; then
		echo $(grep 'dbms.connector.bolt.listen_address=:*' $instances/$name/conf/neo4j.conf | cut -d ":" -f2)
	else
		echo "instance is not running."
		return 1
	fi
}


find_neo4j_instance_http_port()
{
	name=$1
	if instance_has_pid $name; then
		echo $(grep 'dbms.connector.http.listen_address=:*' $instances/$name/conf/neo4j.conf | cut -d ":" -f2)
	else
		echo "instance is not running."
		return 1
	fi
}


find_neo4j_instance_https_port()
{
	name=$1
	if instance_has_pid $name; then
		echo $(grep 'dbms.connector.https.listen_address=:*' $instances/$name/conf/neo4j.conf | cut -d ":" -f2)
	else
		echo "instance is not running."
		return 1
	fi
}

instance_has_pid()
{
	name=$1
	res=`command $instances/$name/bin/neo4j status`
	if [ $? -eq 0 ]; then
		return 0
	else
		return 1
	fi
}

find_neo4j_instance_pid()
{
	name=$1
	res=`command $instances/$name/bin/neo4j status`
	if [ $? -eq 0 ]; then
		neo4j_pid=$(echo $res | cut -d ' ' -f 6-)
		echo $neo4j_pid
	else
		echo 'instance is not running'
	fi
}

log_neo4j_instance()
{
	cat $instances/$1/logs/neo4j.log
}

debug_neo4j_instance()
{
	cat $instances/$1/logs/debug.log
}

case "$1" in
	"start")
		start_neo4j_instances $2
		;;

	"stop")				
		stop_neo4j_instances $2
		;;

	"restart")				
		restart_neo4j_instances $2
		;;

	"create")
		create_new_instance $2
		;;

	"config")
		config_neo4j_instances $2
		;;

	"state")
		state_neo4j_instances $2
		;;

	"delete")
		delete_neo4j_instances $2
		;;

	"find_bolt_port")
		find_neo4j_instance_bolt_port $2
		;;

	"find_http_port")
		find_neo4j_instance_http_port $2
		;;

	"find_https_port")
		find_neo4j_instance_https_port $2
		;;

	"find_pid")
		find_neo4j_instance_pid $2
		;;

	"log_neo4j")
		log_neo4j_instance $2
		;;

	"debug_neo4j")
		debug_neo4j_instance $2
		;;

	"initialize")
		initialize
		;;

	"find_all_instances")
		find_all_neo4j_instances_list
		;;

	"find_running_instances")
		find_running_neo4j_instances_list
		;;

	*) 
		echo "Wrong Parameter"; 
		exit 1 
		;;
esac