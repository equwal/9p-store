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
