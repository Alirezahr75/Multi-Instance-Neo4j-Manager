# Multiple-Instances-Neo4j-Manager

neo4j_manager provides the functionalities to create, run, config and manage multiple standalone instances of neo4j with "apoc" and "gds" plugin on a single machine.

## Installation

Download neo4j-community-Versions-unix.tar.gz in /src

Download apoc-Versions-core.jar in /plugins

Download neo4j-graph-data-science-Versions-standalone.jar in /plugins

```bash
cd /src
	wget https://dist.neo4j.org/neo4j-community-${Versions[neo4j]}-unix.tar.gz -P `pwd`

cd /plugins
	wget https://github.com/neo4j-contrib/neo4j-apoc-procedures/releases/download/${Versions[neo4j_apoc]}/apoc-${Versions[neo4j_apoc]}-core.jar -P `pwd`
	wget https://github.com/neo4j/graph-data-science/releases/download/${Versions[neo4j_gds]}/neo4j-graph-data-science-${Versions[neo4j_gds]}-standalone.jar -P `pwd`
	
Declare Your Version in manage.sh (line 13)
```

## Main Usage

```bash
# initialize and create default instance
./manage.sh initialize

# create new instance
./manage.sh create instance_name

# config an instance
./manage.sh config instance_name

# start an instance
./manage.sh start instance_name

# stop an instance
./manage.sh stop instance_name

# restart an instance
./manage.sh restart instance_name

# find status of an instance
./manage.sh state instance_name

# delete an instance
./manage.sh delete instance_name

# restart an instance
./manage.sh restart instance_name

```

## Contributing
Pull requests are welcome. 

For major changes, please open an issue first to discuss what you would like to change.

## License
https://github.com/Alirezahr75
