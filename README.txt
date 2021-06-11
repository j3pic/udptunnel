USAGE:

   udptunnel [<host>] <port> [-e shellcommand]

This program is designed to tunnel a UDP port through a shell command. If used carefully,
it can be used to send UDP through a firewall that normally only supports TCP.

On a machine that is cut off from being able to use UDP, run it like this:

  udptunnel $port -e "ssh proxy-host udptunnel $host $port"

...where "proxy-host" is an SSH server with its own copy of "udptunnel" that can perform two-way UDP
communication with the final destination machine at $host:$port.

Then, have your local UDP application connect to localhost:$port instead of $host:$port. The datagrams will
be forwarded through the SSH connection and onward to $host:$port. Return traffic will be forwarded back.

It might also be possible to use netcat on the firewalled end and inetd on the proxy end.
