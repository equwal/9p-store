# 9p-store

A small, disk-backed 9P file server for a private network. It uses diod
(Debian package) because plan9port has no persistent disk server: its ramfs
keeps files in RAM only. diod idles at under 1 MB of memory.

## Server

```sh
LISTEN_ADDR=10.0.0.1 ./install.sh
```

The unit listens on `$LISTEN_ADDR` and on 127.0.0.1 (for SSH tunnels), with a
64 MB memory cap and restart on failure.

### Security

diod runs with no 9P authentication (`-n`). Access control is the network:

- Bind only to a private address, for example a WireGuard interface.
- Drop traffic to that address unless it arrives on the private interface:

  ```sh
  nft add rule inet filter input ip daddr 10.0.0.1 iifname != "wg0" drop
  ```

- Check that nothing listens on a public address: `ss -ltnp | grep :564`.
- Never store secrets in the export.

Hosts outside the private network can reach the loopback listener through an
SSH forward limited with `permitopen="127.0.0.1:564"` in `authorized_keys`.

## Clients

### Linux kernel (v9fs)

Needs `CONFIG_9P_FS` and `CONFIG_NET_9P` (`modprobe 9p`).

```sh
mount -t 9p -o trans=tcp,port=564,aname=/srv/9pstore,version=9p2000.L,access=any 10.0.0.1 /mnt/9pstore
```

Through an SSH tunnel:

```sh
ssh -fN -L 127.0.0.1:5640:127.0.0.1:564 tunnel@server
mount -t 9p -o trans=tcp,port=5640,aname=/srv/9pstore,version=9p2000.L,access=any 127.0.0.1 /mnt/9pstore
```

### plan9port

```sh
9p -a tcp!10.0.0.1!564 -A /srv/9pstore ls /
9p -a tcp!10.0.0.1!564 -A /srv/9pstore read /file.txt
echo hi | 9p -a tcp!10.0.0.1!564 -A /srv/9pstore write /file.txt
9pfuse -A /srv/9pstore 'tcp!10.0.0.1!564' /mnt/9pstore
```

### diod tools

```sh
diodls -s 127.0.0.1:564 -a /srv/9pstore
diodcat -s 127.0.0.1:564 -a /srv/9pstore file.txt
```

Windows has no built-in 9P TCP client; use a Linux host or plan9port.

### Client behind a WireGuard sidecar container

A host without its own WireGuard interface can run a small container that
holds the tunnel and forwards 9P to the host's loopback. Placeholders:
`SERVER_WG_IP`, `CLIENT_WG_IP`, `SERVER_PUBKEY`, `SERVER_HOST`.

```sh
# entrypoint.sh (alpine + wireguard-tools-wg, iproute2-minimal, socat)
ip link add wg0 type wireguard
wg set wg0 private-key /keys/privatekey peer SERVER_PUBKEY \
  endpoint SERVER_HOST:51820 allowed-ips SERVER_WG_IP/32 persistent-keepalive 25
ip addr add CLIENT_WG_IP/32 dev wg0
ip link set wg0 up
ip route add SERVER_WG_IP/32 dev wg0
exec socat TCP-LISTEN:564,fork,reuseaddr TCP:SERVER_WG_IP:564
```

```sh
docker run -d --name wg-9p --restart unless-stopped --cap-drop ALL \
  --cap-add NET_ADMIN --memory 32m -v "$PWD/privatekey:/keys/privatekey:ro" \
  -p 127.0.0.1:564:564 wg-9p
mount -t 9p -o trans=tcp,port=564,aname=/srv/9pstore,version=9p2000.L 127.0.0.1 /mnt/9pstore
```

The server needs a `[Peer]` with the container's public key and
`AllowedIPs = CLIENT_WG_IP/32`. One sidecar can forward several services.
