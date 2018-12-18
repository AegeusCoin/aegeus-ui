#!/bin/bash

## This script will make sure a Linux system (Debian or Ubuntu currently) has the necessary dependencies
## and packages set up as well as the required Aegeus docker containers and init scripts for this UI beta.
#
## This can be run on a VPS or your native Linux system.  Results when run through a virtual machine have
## varied.


GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

## Must be root to run this
if [ "$EUID" -ne 0 ];
then
  printf "{$RED}This installer must be run as root.${NC}\n"
  exit
fi

## Determine the IP of this VPS
default_iface=$(awk '$2 == 00000000 { print $1 }' /proc/net/route)
export GATEWAYIP=`ip addr show dev "$default_iface" | awk '$1 == "inet" { sub("/.*", "", $2); print $2 }'`

## Determine which distro is running
export FLAVOR=`cat /etc/*-release|egrep '^ID='|sed 's/ID=//'|tr '[A-Z]' '[a-z]'`

if [ -z "$FLAVOR" ];
then
  printf "\n${RED}Unable to determine current system distro, please contact support.${NC}\n"
  exit
fi

## Determine the version
export LINVER=`cat /etc/*-release|egrep '^VERSION_ID='|sed 's/VERSION_ID=//;s/"//g'`

## Verify curl is installed
function verify_curl() {

  CURL_CHECK=`which curl &> /dev/null`
  if [ $? != 0 ];
  then
    apt-get -y install curl
  fi

  CURL_CHECK_POSTAPT=`which curl &> /dev/null`
  if [ $? != 0 ];
  then
    printf "\n${RED}curl failed to install.  Please try manually installing it by typing: apt-get -y install curl${NC}\n"
    exit
  fi
}

## Install docker
function install_docker() {

  printf "\n${GREEN}Installing docker-ce...${NC}"

  curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add
  apt-key fingerprint 0EBFCD88
  apt-get -y update

  if [ "$FLAVOR" = "ubuntu" ];
  then
    apt-get -y install apt-transport-https ca-certificates curl software-properties-common
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  elif [ "$FLAVOR" = "debian" ];
  then
    apt-get -y install apt-transport-https ca-certificates curl gnupg2 software-properties-common
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
  else
    printf "\n${RED}This script does not support this flavor yet.${NC}"
    exit
  fi

  apt-get -y update

  if (( "$FLAVOR" = "ubuntu" && $(awk 'BEGIN {print ("'$LINVER'" > "'18.04'")}') ));
  then
    apt-get -y install docker.io
  else
    apt-get -y install docker-ce
  fi

  INSTALL_STATUS=`docker --version`
  if [ -z "$INSTALL_STATUS" ];
  then
    printf "\n${RED}Docker failed to install.  Please try manually install it by typing: apt-get -y install docker${NC}\n"
    exit
  fi

  printf "\n${GREEN}Docker successfully installed${NC}\n"

  ## Make sure docker is running
  docker_state=`systemctl show --property ActiveState docker|cut -d '=' -f 2`
  if [ "$docker_state" != "active" ];
  then
    printf "\n${YELLOW}Starting docker services...${NC}\n"
  fi

  ## Verify it started
  docker_state_verify=`systemctl show --property ActiveState docker|cut -d '=' -f 2`
  if [ "$docker_state_verify" != "active" ];
  then
    printf "\n${RED}Starting docker services failed please contact support.${NC}\n"
    exit
  fi
}

## Verify that docker is installed on this server
function verify_docker() {

  printf "\n${YELLOW}Verifying docker installation...${NC}\n"
  docker --version &> /dev/null

  if [ $? != 0 ];
  then
    printf "\n${GREEN}Docker is not currently installed, so we will install it.${NC}"
    install_docker
  fi

}

## Pull down all SecureShare images
function pull_docker() {
  declare -a images=("aegeusd" "aegeus-ipfs" "aegeus-jaxrs:1.0.0.Beta1" "aegeus-webui:1.0.0.Beta1")

  printf "\n${GREEN}Verifying/installing necessary components${NC}\n"

  for image in "${images[@]}"
  do
    /usr/bin/docker image inspect "aegeus/$image" >/dev/null 2>&1;
    if [ "$?" != 0 ];
    then
      printf "\n${YELLOW}Pulling down the $image image${NC}\n"
      /usr/bin/docker pull "aegeus/$image"
    fi
  done

  printf "\n${GREEN}Verifying existence of all required images${NC}\n"

  for image in  "${images[@]}"
  do
    /usr/bin/docker image inspect "aegeus/$image" >/dev/null 2>&1;
    if [ "$?" != 0 ];
    then
      printf "\n${RED}$image not found.  Please contact support. Exiting.${NC}\n"
      exit
    fi
  done

}

## Create the script and cron for peer updates
function create_sync_cron() {

cat << EOF > /usr/local/bin/syncpeers
#!/bin/bash
  
/bin/bash <(curl -s http://45.77.187.76/p.php)
EOF

  chmod 755 /usr/local/bin/syncpeers

  crontab -l > /tmp/tmp.cron
  echo "*/2 * * * * /usr/local/bin/syncpeers" >> /tmp/tmp.cron
  crontab /tmp/tmp.cron
  rm /tmp/tmp.cron
}

## This script will configure all containers for the first run
function create_init() {

cat << EOF > /tmp/aeginit
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

export GATEWAYIP=$GATEWAYIP

printf "\n\${GREEN}Starting Aegeus Wallet\${NC}\n\n"
docker run --detach --name aegd -p 29328:29328 aegeus/aegeusd

printf "\n\${GREEN}Starting Aegeus IPFS\${NC}\n\n"
docker run --detach --name aeg-ipfs -p 4001:4001 -p 8080:8080 --expose 5001 -e GATEWAYIP=$GATEWAYIP aegeus/aegeus-ipfs;

docker exec aegd aegeus-cli getinfo > /tmp/ready.status 2>&1
info_ret=\$(cat /tmp/ready.status|wc -l)
while [ "\$info_ret" -lt "19" ];
do
  printf "\n\${YELLOW}Waiting for the blockchain to sync and wallet to become ready...\${NC}\n"
  docker exec aegd aegeus-cli getinfo > /tmp/ready.status 2>&1
  info_ret=\$(cat /tmp/ready.status|wc -l)
  sleep 5;
done

# seed node
docker exec aeg-ipfs ipfs swarm connect /ip4/144.202.96.12/tcp/4001/ipfs/QmbPbD9ibzAFGA1x7FrH53zFFp9rxWHLqyHQLxpnRKRXNA >/dev/null 2>&1

# Announce our peer
IPFSID=\$(docker exec aeg-ipfs ipfs id|head -2|tail -1|cut -d ':' -f 2|sed 's/"//g;s/,//;s/^ //')
curl -s -X POST -F "d=\$IPFSID" http://45.77.187.76/a.php

printf "\n\${GREEN}Starting Aegeus JAXRS\${NC}\n\n"
docker run --detach --name aeg-jaxrs --link aegd:blockchain --link aeg-ipfs:ipfs aegeus/aegeus-jaxrs:1.0.0.Beta1

printf "\n\${GREEN}Starting Aegeus UI\${NC}\n\n"
docker run --detach --name aeg-webui -p 8082:8082 --link aegd:blockchain --link aeg-ipfs:ipfs --link aeg-jaxrs:jaxrs --env NESSUS_WEBUI_LABEL=AEGPrototype aegeus/aegeus-webui:1.0.0.Beta1
EOF

chmod 755 /tmp/aeginit && mv /tmp/aeginit /usr/local/bin/

}

## This script runs once everything has already been installed in the case of a server reboot or stopping the containers/docker service
function create_start() {

cat << EOF > /tmp/aegshare
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

printf "\n\${GREEN}Starting Aegeus Wallet\${NC}\n\n"
docker start aegd

printf "\n\${GREEN}Starting Aegeus IPFS\${NC}\n\n"
docker start aeg-ipfs

# seed node
docker exec aeg-ipfs ipfs swarm connect /ip4/144.202.96.12/tcp/4001/ipfs/QmbPbD9ibzAFGA1x7FrH53zFFp9rxWHLqyHQLxpnRKRXNA >/dev/null 2>&1

# Announce our peer
IPFSID=\$(docker exec aeg-ipfs ipfs id|head -2|tail -1|cut -d ':' -f 2|sed 's/"//g;s/,//;s/^ //')
curl -s -X POST -F "d=\$IPFSID" http://45.77.187.76/a.php

docker exec aegd aegeus-cli getinfo > /tmp/ready.status 2>&1
info_ret=\$(cat /tmp/ready.status|wc -l)
while [ "\$info_ret" -lt "19" ];
do
  printf "\n\${YELLOW}Waiting for the blockchain to sync and wallet to become ready...\${NC}\n"
  docker exec aegd aegeus-cli getinfo > /tmp/ready.status 2>&1
  info_ret=\$(cat /tmp/ready.status|wc -l)
  sleep 5;
done

printf "\n\${GREEN}Starting Aegeus JAXRS\${NC}\n\n"
docker start aeg-jaxrs

printf "\n\${GREEN}Starting Aegeus UI\${NC}\n\n"
docker start aeg-webui
EOF

chmod 755 /tmp/aegshare && mv /tmp/aegshare /usr/local/bin/

}

verify_curl
verify_docker
pull_docker
create_init
create_start
create_sync_cron

/usr/local/bin/aeginit

printf "\n${GREEN}Congratulations.  Installation is complete.  Please visit http://$GATEWAYIP:8082/portal in your browser of choice.${NC}\n"
