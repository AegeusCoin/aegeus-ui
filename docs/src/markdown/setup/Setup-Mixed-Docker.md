## Local setup with mixed services

This type of installation requires a working [Docker](https://www.docker.com/community-edition#/download) environment.

In total there are four Docker images to make up the complete system.

1. [aegeus/aegeusd](https://hub.docker.com/r/aegeus/aegeusd)
2. [aegeus/aegeus-ipfs](https://hub.docker.com/r/aegeus/aegeus-ipfs)
3. [aegeus/aegeus-jaxrs](https://hub.docker.com/r/aegeus/aegeus-jaxrs)
4. [aegeus/aegeus-webui](https://hub.docker.com/r/aegeus/aegeus-webui)

What follows is an installation guide for the last two containers.
It is assumed that you already have a local IPFS and AEG wallet running.

### Running the AEG JAXRS image

This is the JSON-RPC bridge, which contains the Aegeus application logic that connects the Aegeus network with IPFS network.

#### Bind the Aegeus wallet to an external IP

For this to work, your Aegeus wallet needs to bind to an external IP

    server=1
    txindex=1
    rpcuser=aeg
    rpcpassword=aegpass
    rpcport=51473
    rpcconnect=192.168.178.20
    rpcallowip=192.168.178.20
    wallet=test-wallet.dat

Verify that this works

    export LOCALIP=192.168.178.20
    curl --data-binary '{"method": "getinfo"}' http://aeg:aegpass@$LOCALIP:51473

Then, verify that this also works from within docker

    docker run -it --rm --entrypoint=bash aegeus/aegeus-jaxrs

    export LOCALIP=192.168.178.20
    curl --data-binary '{"method": "getinfo"}' http://aeg:aegpass@192.168.178.20:51473

#### Bind the IPFS daemon to an external IP

For this to work, your IPFS daemon needs to bind to an external IP

    ipfs config Addresses.API "/ip4/0.0.0.0/tcp/5001"
    ipfs config Addresses.Gateway "/ip4/0.0.0.0/tcp/8080"
    ipfs daemon &
    ...
    API server listening on /ip4/0.0.0.0/tcp/5001
    Gateway (readonly) server listening on /ip4/0.0.0.0/tcp/8080
    Daemon is ready

Verify that this works

    export LOCALIP=192.168.178.20
    ipfs --api=/ip4/$LOCALIP/tcp/5001 version

#### Run the AEG JAXRS image

To start the Aegeus bridge in Docker, you can run ...

    export LOCALIP=192.168.178.20

    docker run --detach \
        --env IPFS_PORT_5001_TCP_ADDR=$LOCALIP \
        --env IPFS_PORT_5001_TCP_PORT=5001 \
        --env IPFS_PORT_8080_TCP_ADDR=$LOCALIP \
        --env IPFS_PORT_8080_TCP_PORT=8080 \
        --env AEG_PORT_51473_TCP_ADDR=$LOCALIP \
        --env AEG_PORT_51473_TCP_PORT=51473 \
        --env AEG_ENV_RPCUSER=aeg \
        --env AEG_ENV_RPCPASS=aegpass \
        --memory=200m --memory-swap=2g \
        --name aeg-jaxrs \
        aegeus/aegeus-jaxrs

On bootstrap the bridge reports some connection properties.

    docker logs aeg-jaxrs

    AegeusBlockchain: http://aeg:*******@192.168.178.20:51473
    AegeusNetwork Version: 2000000
    IPFS Version: 0.4.16
    Aegeus JAXRS: http://0.0.0.0:8081/aegeus

### Running the AEG WebUI image

In this setup the Aegeus UI is optional as well. Still, lets try to connect it to the JSON-RPC bridge and the Aegeus wallet  ...

    export LABEL=Mary

    docker run --detach \
        -p 8082:8082 \
        --link aeg-jaxrs:jaxrs \
        --env IPFS_ENV_GATEWAYIP=$LOCALIP \
        --env IPFS_PORT_8080_TCP_ADDR=$LOCALIP \
        --env IPFS_PORT_8080_TCP_PORT=8080 \
        --env AEG_PORT_51473_TCP_ADDR=$LOCALIP \
        --env AEG_PORT_51473_TCP_PORT=51473 \
        --env AEG_ENV_RPCUSER=aeg \
        --env AEG_ENV_RPCPASS=aegpass \
        --env NESSUS_WEBUI_LABEL=$LABEL \
        --memory=200m --memory-swap=2g \
        --name aeg-webui \
        aegeus/aegeus-webui

The WebUI also reports some connection properties.

    docker logs aeg-webui

    AEG JAXRS: http://172.17.0.3:8081/aegeus
    IPFS Gateway: http://192.168.178.20:8080/ipfs
    AEG WebUI: http://0.0.0.0:8082/portal
    AegeusBlockchain: http://aeg:*******@192.168.178.20:51473
    AegeusNetwork Version: 3000000

You should now be able to access the WebUI at: [http://127.0.0.1:8082/portal](http://127.0.0.1:8082/portal)

Everything else should work as described [here](Setup-All-Docker.md).

That's it - Enjoy!

