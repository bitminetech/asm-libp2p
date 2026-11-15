# Shell

## Contents

### Functions

- [`libp2p_shell_size`](#function-libp2p_shell_size): gives the bytes of a shell context.
- [`libp2p_shell_init`](#function-libp2p_shell_init): builds a shell context.
- [`libp2p_shell_listen`](#function-libp2p_shell_listen): opens a listening socket.
- [`libp2p_shell_bind`](#function-libp2p_shell_bind): opens a bound UDP socket.
- [`libp2p_shell_perform`](#function-libp2p_shell_perform): performs the shell actions of a step.
- [`libp2p_shell_wait`](#function-libp2p_shell_wait): waits for socket activity.
- [`libp2p_shell_close`](#function-libp2p_shell_close): closes every socket.
- [`libp2p_shell_clock`](#function-libp2p_shell_clock): reads the time and random bytes.
- [`libp2p_shell_sockaddr`](#function-libp2p_shell_sockaddr): builds a native socket address.
- [`libp2p_shell_address`](#function-libp2p_shell_address): reads a native socket address.
- [`libp2p_shell_layout`](#function-libp2p_shell_layout): checks the parameters and lays out a context.
- [`libp2p_shell_entry`](#function-libp2p_shell_entry): finds the entry of a connection.
- [`libp2p_shell_event`](#function-libp2p_shell_event): adds an event.
- [`libp2p_shell_room`](#function-libp2p_shell_room): gives the room of an event list.
- [`libp2p_shell_conn_event`](#function-libp2p_shell_conn_event): adds an event of a connection.
- [`libp2p_shell_drop`](#function-libp2p_shell_drop): closes the socket of a connection.
- [`libp2p_shell_flush`](#function-libp2p_shell_flush): writes the send buffer of a connection.
- [`libp2p_shell_move`](#function-libp2p_shell_move): moves bytes down.
- [`libp2p_shell_move_any`](#function-libp2p_shell_move_any): copies bytes.
- [`libp2p_shell_accept`](#function-libp2p_shell_accept): accepts one connection.
- [`libp2p_shell_poll_set`](#function-libp2p_shell_poll_set): writes one poll entry.
- [`libp2p_shell_poll_events`](#function-libp2p_shell_poll_events): reads the events of a poll entry.
- [`libp2p_shell_fcntl`](#function-libp2p_shell_fcntl): calls fcntl.
- [`libp2p_shell_prepare`](#function-libp2p_shell_prepare): prepares a socket.
- [`libp2p_shell_socket`](#function-libp2p_shell_socket): opens a socket.
- [`libp2p_shell_accept_one`](#function-libp2p_shell_accept_one): accepts a socket.
- [`libp2p_shell_wsa_start`](#function-libp2p_shell_wsa_start): starts Winsock.
- [`libp2p_shell_wsa_end`](#function-libp2p_shell_wsa_end): stops Winsock.
- [`libp2p_shell_nonblock`](#function-libp2p_shell_nonblock): makes a socket non-blocking.
- [`libp2p_shell_poll`](#function-libp2p_shell_poll): waits with WSAPoll.
- [`libp2p_shell_udp_read`](#function-libp2p_shell_udp_read): reads the datagrams of a UDP socket.
- [`libp2p_shell_udp_socket`](#function-libp2p_shell_udp_socket): opens a non-blocking UDP socket.
- [`libp2p_shell_no_connreset`](#function-libp2p_shell_no_connreset): turns off WSAECONNRESET on a UDP socket.

### Types

- [`ShellParams`](#type-shellparams): the parameters of a shell context.
- [`ShellContext`](#type-shellcontext): the sockets of the shell.
- [`ShellEntry`](#type-shellentry): the socket of one connection.
- [`ListenResult`](#type-listenresult): the outcome of `libp2p_shell_listen`.
- [`BindResult`](#type-bindresult): the outcome of `libp2p_shell_bind`.

### Constants

- `LIBP2P_OS_ERROR`: status 8: an OS call failed.
- `LIBP2P_SHELL_ACCEPTING`: accepted sockets that may wait for ADOPT.
- `LIBP2P_RECEIVE_MAX`: bytes of one RECEIVED event.
- `LIBP2P_SH_MAX_UDP`: UDP sockets of a context, at most.
- `LIBP2P_UDP_RECEIVE`: bytes of the largest datagram the shell reads.
- `LIBP2P_UDP_BUFFER`: the send and receive buffer bytes a UDP socket asks for.

## Spec

- Document: ARCHITECTURE.md section 2 (core and shell) and section 6 (actions and events).
- Section: the shell of this library: TCP and UDP sockets, the clock and random bytes, for Linux (system calls), macOS (libSystem) and Windows (Winsock 2, kernel32, bcrypt).

## Function `libp2p_shell_size`

Gives the bytes of a shell context for its parameters.

### Signature

```
libp2p_shell_size(params, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `params` | input | [`ShellParams`](#type-shellparams) |
| `size` | output | u64 |

### Returns

- `LIBP2P_OK`: `size` holds the bytes.
- `LIBP2P_INVALID_CONFIG`: `capacity` is not 1 to 65536, or `buffer` is not 4096 to 2^30.

### Function does

- Adds the fixed fields, 16 accepted sockets, the poll array (listening, UDP, accepted and connection sockets) and one entry with its send buffer for each connection.

### Function never

- Writes more than `size` and its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on Linux x86-64, 96 bytes on Linux ARM64, 112 bytes on Linux RISC-V, 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_size` (`_libp2p_shell_size` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `params`, `size`.

## Function `libp2p_shell_init`

Builds a shell context with no sockets.

### Signature

```
libp2p_shell_init(params, context) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `params` | input | [`ShellParams`](#type-shellparams) |
| `context` | output | [`ShellContext`](#type-shellcontext) |

### Returns

- `LIBP2P_OK`: The context is ready.
- `LIBP2P_INVALID_CONFIG`: As `libp2p_shell_size`.
- `LIBP2P_BUFFER_TOO_SMALL`: The `size` field of the context is below what `libp2p_shell_size` gives.
- `LIBP2P_OS_ERROR`: Windows: WSAStartup failed.

### Caller must

- Set the `size` field of the context.
- Pass the `max_connections` and `send_window` of the node config, or more.

### Function does

- Writes the fixed fields and marks every socket unused: listening, UDP, accepted and connection sockets.
- Windows: starts Winsock 2.2, and records that it did.

### Function never

- Writes more than the context and its own stack.

### Limits

- Stack of its own: 112 bytes on Linux x86-64, 96 bytes on Linux ARM64, 112 bytes on Linux RISC-V, 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_init` (`_libp2p_shell_init` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `params`, `context`.

## Function `libp2p_shell_listen`

Opens a TCP socket that listens on an address.

### Signature

```
libp2p_shell_listen(context, addr, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | resource context | [`ShellContext`](#type-shellcontext) |
| `addr` | input | [`Address`](node.md#type-address); port 0: any |
| `result` | output | [`ListenResult`](#type-listenresult) |

### Returns

- `LIBP2P_OK`: `result` holds error 0 and the bound address, or the OS error.

### Function does

- Opens a non-blocking socket, sets the listener option (Linux and macOS SO_REUSEADDR, Windows SO_EXCLUSIVEADDRUSE), and IPV6_V6ONLY on IPv6, then binds and listens with a backlog of 1024.
- Writes the bound address, with the port the OS chose for port 0.
- Gives the error EINVAL (WSAEINVAL on Windows) when 4 sockets listen already.

### Limits

- Stack of its own: 304 bytes on Linux x86-64, 256 bytes on Linux ARM64, 272 bytes on Linux RISC-V, 304 bytes on macOS x86-64, 256 bytes on macOS ARM64, 304 bytes on Windows x86-64, 256 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_listen` (`_libp2p_shell_listen` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`, `addr`, `result`.

## Function `libp2p_shell_bind`

Opens a UDP socket bound to an address, for QUIC.

### Signature

```
libp2p_shell_bind(context, addr, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | resource context | [`ShellContext`](#type-shellcontext) |
| `addr` | input | [`Address`](node.md#type-address); port 0: any |
| `result` | output | [`BindResult`](#type-bindresult) |

### Returns

- `LIBP2P_OK`: `result` holds error 0, the socket ID and the bound address, or the OS error.

### Function does

- Opens a non-blocking UDP socket: Linux with SOCK_NONBLOCK and SOCK_CLOEXEC; macOS with `libp2p_shell_udp_socket`, which adds FD_CLOEXEC and SO_NOSIGPIPE; Windows with `libp2p_shell_udp_socket`, which turns off WSAECONNRESET.
- Sets IPV6_V6ONLY on IPv6.
- Asks for send and receive buffers of `LIBP2P_UDP_BUFFER` bytes; the OS may give less.
- Binds, then writes the bound address, with the port the OS chose for port 0.
- Gives the socket the next socket ID, from 0: DIAL, DATAGRAM and SEND_DATAGRAM name the socket by it.
- Gives the error EINVAL (WSAEINVAL on Windows) when `LIBP2P_SH_MAX_UDP` sockets are bound already.

### Limits

- Stack of its own: 304 bytes on Linux x86-64, 256 bytes on Linux ARM64, 272 bytes on Linux RISC-V, 304 bytes on macOS x86-64, 256 bytes on macOS ARM64, 304 bytes on Windows x86-64, 256 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_bind` (`_libp2p_shell_bind` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`, `addr`, `result`.

## Function `libp2p_shell_perform`

Performs the shell actions of a step, in order.

### Signature

```
libp2p_shell_perform(context, actions, events) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | resource context | [`ShellContext`](#type-shellcontext) |
| `actions` | input | [`ByteList`](node.md#type-bytelist) of [`Action`](node.md#type-action) values |
| `events` | output | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |

### Returns

- `LIBP2P_OK`: The actions are done; results known at once are events.

### Caller must

- Pass the action list of `libp2p_step`, before the next step.
- Keep room in the event list for the results.

### Function does

- DIAL: opens a non-blocking socket with TCP_NODELAY and connects; gives CONNECTED when it connects at once, DIAL_FAILED with the OS error when it fails, and nothing while it is in progress.
- ADOPT: binds the accepted socket of the token to the connection; REFUSE: closes it.
- SEND: adds the bytes to the send buffer of the connection and writes what the socket takes: SENT; bytes past the buffer close the connection with CLOSED and EINVAL.
- CLOSE: closes the socket and gives CLOSED, also when the shell holds no socket for the handle.
- SEND_DATAGRAM: `sendto` on the UDP socket of its ID, without blocking; a datagram the OS does not take is lost, as UDP allows, and QUIC sends it again.
- Skips the other action kinds: they are for the application.

### Limits

- Stack of its own: 304 bytes on Linux x86-64, 256 bytes on Linux ARM64, 272 bytes on Linux RISC-V, 304 bytes on macOS x86-64, 256 bytes on macOS ARM64, 304 bytes on Windows x86-64, 256 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_perform` (`_libp2p_shell_perform` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`, `actions`, `events`.

## Function `libp2p_shell_wait`

Waits for socket activity and gives events.

### Signature

```
libp2p_shell_wait(context, timeout, events) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | resource context | [`ShellContext`](#type-shellcontext) |
| `timeout` | input | u64: ms |
| `events` | output | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |

### Returns

- `LIBP2P_OK`: The wait ended; the events tell what happened.

### Function does

- Waits up to the timeout, at most 2^31 - 1 ms on macOS and Windows, with ppoll, poll or WSAPoll, on the listening, UDP and connection sockets in one call.
- ACCEPTED for each new connection, while fewer than 16 wait for ADOPT and the event list has room; others stay in the backlog.
- CONNECTED or DIAL_FAILED (with SO_ERROR) when a dial ends.
- SENT as buffered bytes go out.
- RECEIVED with what a socket holds: at most `LIBP2P_RECEIVE_MAX` bytes and the room of the event list.
- CLOSED when the peer closes a socket (error 0) or it fails (the OS error).
- DATAGRAM for each datagram a UDP socket holds (`libp2p_shell_udp_read`), while the event list has room.
- Windows: sleeps the timeout when WSAPoll fails, as it does with no socket.

### Limits

- Stack of its own: 304 bytes on Linux x86-64, 256 bytes on Linux ARM64, 272 bytes on Linux RISC-V, 304 bytes on macOS x86-64, 256 bytes on macOS ARM64, 304 bytes on Windows x86-64, 256 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_wait` (`_libp2p_shell_wait` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`, `timeout`, `events`.

## Function `libp2p_shell_close`

Closes every socket of a context.

### Signature

```
libp2p_shell_close(context) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | resource context | [`ShellContext`](#type-shellcontext) |

### Returns

- `LIBP2P_OK`: Every socket is closed.

### Function does

- Closes the listening sockets, the UDP sockets, the accepted sockets that wait, and each connection socket.
- Windows: stops Winsock when `libp2p_shell_init` started it.

### Limits

- Stack of its own: 112 bytes on Linux x86-64, 96 bytes on Linux ARM64, 112 bytes on Linux RISC-V, 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_close` (`_libp2p_shell_close` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`.

## Function `libp2p_shell_clock`

Reads the monotonic time, the Unix time and 32 random bytes.

### Signature

```
libp2p_shell_clock(tick) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `tick` | output | [`Tick`](node.md#type-tick) |

### Returns

- `LIBP2P_OK`: `tick` holds the time and the bytes.
- `LIBP2P_OS_ERROR`: The clock or the random source failed.

### Function does

- Writes the monotonic time in ms and in microseconds, from one reading of the clock, and the Unix time in seconds.
- Linux: `clock_gettime` of CLOCK_MONOTONIC and of CLOCK_REALTIME, and `getrandom`.
- macOS: `clock_gettime_nsec_np` of CLOCK_MONOTONIC and of CLOCK_REALTIME, and `getentropy`.
- Windows: `QueryPerformanceCounter` over `QueryPerformanceFrequency`, `GetSystemTimeAsFileTime`, and `BCryptGenRandom` with the system RNG.

### Function never

- Writes more than `tick` and its own stack.

### Limits

- Stack of its own: 304 bytes on Linux x86-64, 112 bytes on Linux ARM64, 128 bytes on Linux RISC-V, 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 304 bytes on Windows x86-64, 112 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L2.
- Symbol: `libp2p_shell_clock` (`_libp2p_shell_clock` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `tick`.

## Function `libp2p_shell_sockaddr`

Builds a native socket address from an address.

### Signature

```
libp2p_shell_sockaddr(addr, sockaddr) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `addr` | input | [`Address`](node.md#type-address) |
| `sockaddr` | output | 32 bytes |

### Function does

- Writes sockaddr_in (16 bytes) or sockaddr_in6 (28 bytes) with the port big endian; macOS sets `sin_len` too.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_sockaddr`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the length, not a status.
- Argument order: `addr`, `sockaddr`.

## Function `libp2p_shell_address`

Reads a native socket address into an address.

### Signature

```
libp2p_shell_address(sockaddr, addr)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `sockaddr` | input | sockaddr_in or sockaddr_in6 |
| `addr` | output | [`Address`](node.md#type-address) |

### Function does

- Writes the family, port and IP; an IPv4-mapped IPv6 address becomes IPv4.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_address`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `sockaddr`, `addr`.

## Function `libp2p_shell_layout`

Checks the shell parameters and gives the context size.

### Signature

```
libp2p_shell_layout(params, context) -> status, size
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `params` | input | [`ShellParams`](#type-shellparams) |
| `context` | output | [`ShellContext`](#type-shellcontext), or 0 |

### Function does

- Checks `capacity` and `buffer`, and with a context writes its fixed fields.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_layout`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the status in x0, rax or a0 and the size in x1, rdx or a1.
- Argument order: `params`, `context`.

## Function `libp2p_shell_entry`

Finds the connection entry of a handle.

### Signature

```
libp2p_shell_entry(context, handle) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | input | [`ShellContext`](#type-shellcontext) |
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |

### Function does

- Gives the entry of the slot index of the handle, or 0 past the capacity.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_entry`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the entry or 0, not a status.
- Argument order: `context`, `handle`.

## Function `libp2p_shell_event`

Adds one zeroed event to an event list.

### Signature

```
libp2p_shell_event(events, kind, size) -> event
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `events` | state | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |
| `kind` | input | u64 |
| `size` | input | u64: a multiple of 8 |

### Function does

- Writes `size` and `kind` and zeroes the rest; gives 0 when the list has no room.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 96 bytes on Linux ARM64, 112 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 96 bytes on macOS ARM64, 8 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the event or 0, not a status.
- Argument order: `events`, `kind`, `size`.

## Function `libp2p_shell_room`

Gives the bytes left in an event list.

### Signature

```
libp2p_shell_room(events) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `events` | input | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |

### Function does

- Gives size - offset - count, or 0.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the byte count, not a status.
- Argument order: `events`.

## Function `libp2p_shell_conn_event`

Adds an event with a connection handle and a value.

### Signature

```
libp2p_shell_conn_event(events, kind, handle, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `events` | state | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |
| `kind` | input | u64 |
| `handle` | input | u64: a handle ([`Handle`](node.md#type-handle)) |
| `value` | input | u64: an error or a count |

### Function does

- Adds a CONNECTED, DIAL_FAILED, SENT or CLOSED event; drops it when the list has no room.

### Limits

- Stack of its own: 112 bytes on Linux x86-64, 96 bytes on Linux ARM64, 112 bytes on Linux RISC-V, 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_conn_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `events`, `kind`, `handle`, `value`.

## Function `libp2p_shell_drop`

Closes the socket of a connection and gives CLOSED.

### Signature

```
libp2p_shell_drop(entry, events, error)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | [`ShellEntry`](#type-shellentry) |
| `events` | state | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |
| `error` | input | u64: the OS error, or 0 |

### Function does

- Closes the socket, frees the entry, and gives CLOSED with the error.

### Limits

- Stack of its own: 112 bytes on Linux x86-64, 96 bytes on Linux ARM64, 112 bytes on Linux RISC-V, 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_drop`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `entry`, `events`, `error`.

## Function `libp2p_shell_flush`

Writes what the send buffer of a connection holds.

### Signature

```
libp2p_shell_flush(entry, events)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | [`ShellEntry`](#type-shellentry) |
| `events` | state | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |

### Function does

- Writes until the socket would block, keeps the rest at the front, and gives SENT with the bytes written.
- An error closes the connection with `libp2p_shell_drop`, after SENT for the bytes written before it.
- Linux sends with MSG_NOSIGNAL; macOS sockets have SO_NOSIGPIPE.

### Limits

- Stack of its own: 112 bytes on Linux x86-64, 96 bytes on Linux ARM64, 112 bytes on Linux RISC-V, 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_flush`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `entry`, `events`.

## Function `libp2p_shell_move`

Copies n bytes forward; the destination is below the source.

### Signature

```
libp2p_shell_move(dst, src, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n bytes |
| `src` | input | n bytes |
| `n` | input | u64 |

### Function does

- Copies one byte at a time from the first, or with `rep movsb` on x86-64.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_move`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `dst`, `src`, `n`.

## Function `libp2p_shell_move_any`

Copies n bytes between regions that do not overlap.

### Signature

```
libp2p_shell_move_any(dst, src, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n bytes |
| `src` | input | n bytes |
| `n` | input | u64 |

### Function does

- Copies 8 bytes at a time (on RISC-V only when both are 8-byte aligned), then the rest; `rep movsb` on x86-64.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_move_any`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `dst`, `src`, `n`.

## Function `libp2p_shell_accept`

Accepts one connection of a listening socket.

### Signature

```
libp2p_shell_accept(context, events, listener)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | resource context | [`ShellContext`](#type-shellcontext) |
| `events` | state | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |
| `listener` | input | u64: the native socket |

### Function does

- Accepts one socket when one of the 16 places is free and the event list has room for ACCEPTED, sets TCP_NODELAY, keeps the socket in the place, and gives ACCEPTED with the socket as the token.
- Else leaves the connection in the backlog of the OS.

### Limits

- Stack of its own: 304 bytes on Linux x86-64, 256 bytes on Linux ARM64, 272 bytes on Linux RISC-V, 304 bytes on macOS x86-64, 256 bytes on macOS ARM64, 304 bytes on Windows x86-64, 256 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_accept`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`, `events`, `listener`.

## Function `libp2p_shell_poll_set`

Writes one poll entry.

### Signature

```
libp2p_shell_poll_set(socket, events, index, array)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `socket` | input | u64: the native socket, or -1 for none |
| `events` | input | u64: poll events |
| `index` | input | u64 |
| `array` | state | the poll array |

### Function does

- Writes a pollfd (8 bytes) on Linux and macOS, or a WSAPOLLFD (16 bytes) on Windows, with no returned events.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_poll_set`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `socket`, `events`, `index`, `array`.

## Function `libp2p_shell_poll_events`

Reads the returned events of one poll entry.

### Signature

```
libp2p_shell_poll_events(index, array) -> revents
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64 |
| `array` | input | the poll array |

### Function does

- Gives the 16-bit returned events of the entry.

### Limits

- Stack of its own: 8 bytes on Linux x86-64, 0 bytes on Linux ARM64, 0 bytes on Linux RISC-V, 8 bytes on macOS x86-64, 0 bytes on macOS ARM64, 8 bytes on Windows x86-64, 0 bytes on Windows ARM64 (x86-64 return address included).

### ABI

- Role: L0.
- Symbol: `libp2p_shell_poll_events`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns the events, not a status.
- Argument order: `index`, `array`.

## Function `libp2p_shell_fcntl`

Calls `fcntl` with one integer argument.

### Signature

```
libp2p_shell_fcntl(socket, command, value) -> result
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `socket` | input | u64 |
| `command` | input | u64 |
| `value` | input | u64 |

### Function does

- Passes the variadic value as Darwin wants it: on the stack on ARM64, in a register with al = 0 on x86-64.

### Limits

- Stack of its own: 112 bytes on macOS x86-64, 32 bytes on macOS ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_fcntl`, local to its object.
- OS: macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns the result, or minus the error number, not a status.
- Argument order: `socket`, `command`, `value`.

## Function `libp2p_shell_prepare`

Makes a socket non-blocking and close-on-exec, without SIGPIPE.

### Signature

```
libp2p_shell_prepare(socket) -> 0 or error
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `socket` | input | u64 |

### Function does

- Sets O_NONBLOCK and FD_CLOEXEC with `fcntl`, and SO_NOSIGPIPE.

### Limits

- Stack of its own: 304 bytes on macOS x86-64, 256 bytes on macOS ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_prepare`, local to its object.
- OS: macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns 0, or minus the error number, not a status.
- Argument order: `socket`.

## Function `libp2p_shell_socket`

Opens a non-blocking TCP socket.

### Signature

```
libp2p_shell_socket(family) -> socket
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `family` | input | u64: the native address family |

### Function does

- Opens the socket, then macOS: `libp2p_shell_prepare`; Windows: `libp2p_shell_nonblock`.
- Closes it again when that fails.

### Limits

- Stack of its own: 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_socket`, local to its object.
- OS: macOS, Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns the socket, or minus the error number, not a status.
- Argument order: `family`.

## Function `libp2p_shell_accept_one`

Accepts one socket and makes it non-blocking.

### Signature

```
libp2p_shell_accept_one(listener, sockaddr, length) -> socket
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `listener` | input | u64 |
| `sockaddr` | output | 128 bytes |
| `length` | state | u64: bytes of `sockaddr` |

### Function does

- Accepts, then prepares the socket as `libp2p_shell_socket` does.

### Limits

- Stack of its own: 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_accept_one`, local to its object.
- OS: macOS, Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns the socket, or minus the error number, not a status.
- Argument order: `listener`, `sockaddr`, `length`.

## Function `libp2p_shell_wsa_start`

Starts Winsock 2.2 for a context.

### Signature

```
libp2p_shell_wsa_start(context) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | state | [`ShellContext`](#type-shellcontext) |

### Function does

- Calls WSAStartup and records that it started.
- Gives `LIBP2P_OK`, or `LIBP2P_OS_ERROR` when WSAStartup fails.

### Limits

- Stack of its own: 528 bytes on Windows x86-64, 448 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_wsa_start`, local to its object.
- OS: Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns a status.
- Argument order: `context`.

## Function `libp2p_shell_wsa_end`

Stops Winsock when the context started it.

### Signature

```
libp2p_shell_wsa_end(context)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | state | [`ShellContext`](#type-shellcontext) |

### Function does

- Calls WSACleanup once, when the context records a start.

### Limits

- Stack of its own: 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_wsa_end`, local to its object.
- OS: Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`.

## Function `libp2p_shell_nonblock`

Makes a socket non-blocking.

### Signature

```
libp2p_shell_nonblock(socket) -> 0 or error
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `socket` | input | u64: a SOCKET |

### Function does

- Calls ioctlsocket with FIONBIO 1.

### Limits

- Stack of its own: 304 bytes on Windows x86-64, 112 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_nonblock`, local to its object.
- OS: Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns 0, or minus the Winsock error, not a status.
- Argument order: `socket`.

## Function `libp2p_shell_poll`

Waits with WSAPoll, or sleeps when it fails.

### Signature

```
libp2p_shell_poll(array, count, timeout) -> ready
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `array` | state | WSAPOLLFD entries |
| `count` | input | u64 |
| `timeout` | input | u64: ms, at most 2^31 - 1 |

### Function does

- Gives the ready count of WSAPoll.
- When WSAPoll fails, as it does when no entry holds a socket, sleeps the timeout and gives 0.

### Limits

- Stack of its own: 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_poll`, local to its object.
- OS: Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns the ready count, not a status.
- Argument order: `array`, `count`, `timeout`.

## Function `libp2p_shell_udp_read`

Turns the datagrams waiting on a UDP socket into DATAGRAM events.

### Signature

```
libp2p_shell_udp_read(context, events, index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | resource context | [`ShellContext`](#type-shellcontext) |
| `events` | output | [`ByteList`](node.md#type-bytelist) of [`Event`](node.md#type-event) values |
| `index` | input | u64: the UDP socket ID |

### Function does

- While the event list has room for a DATAGRAM event of `LIBP2P_UDP_RECEIVE` bytes: `recvfrom` without blocking into the next event, then sets its size, kind, socket ID, count and sender address.
- Stops at an error, such as an empty socket.
- A datagram longer than `LIBP2P_UDP_RECEIVE` bytes does not arrive whole.

### Limits

- Stack of its own: 304 bytes on Linux x86-64, 256 bytes on Linux ARM64, 272 bytes on Linux RISC-V, 304 bytes on macOS x86-64, 256 bytes on macOS ARM64, 304 bytes on Windows x86-64, 256 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_udp_read`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `context`, `events`, `index`.

## Function `libp2p_shell_udp_socket`

Opens a non-blocking UDP socket.

### Signature

```
libp2p_shell_udp_socket(family) -> socket
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `family` | input | u64: the native address family |

### Function does

- Opens the socket, then macOS: `libp2p_shell_prepare`; Windows: `libp2p_shell_nonblock`, then `libp2p_shell_no_connreset`.
- Closes it again when `libp2p_shell_prepare` or `libp2p_shell_nonblock` fails.

### Limits

- Stack of its own: 112 bytes on macOS x86-64, 96 bytes on macOS ARM64, 112 bytes on Windows x86-64, 96 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_udp_socket`, local to its object.
- OS: macOS, Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention. It returns the socket, or minus the error number, not a status.
- Argument order: `family`.

## Function `libp2p_shell_no_connreset`

Turns off WSAECONNRESET on a UDP socket.

### Signature

```
libp2p_shell_no_connreset(socket)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `socket` | input | u64 |

### Function does

- `WSAIoctl` SIO_UDP_CONNRESET with FALSE: an ICMP port unreachable then does not fail the next `recvfrom`.
- Ignores a failure: reads still work.

### Limits

- Stack of its own: 96 bytes on Windows x86-64, 48 bytes on Windows ARM64 (x86-64 return address included). OS calls add their own.

### ABI

- Role: L0.
- Symbol: `libp2p_shell_no_connreset`, local to its object.
- OS: Windows.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); OS calls use the native convention.
- Argument order: `socket`.

## Type `ShellParams`

The size of a shell context.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `capacity` | u64 | Connection slots: `max_connections` of the node config, 1 to 65536 |
| 8 | `buffer` | u64 | Send buffer bytes of a connection: at least `send_window`, 4096 to 2^30 |

### Rules

- A SEND action never holds more than `send_window` bytes in flight, so a buffer of `send_window` bytes always holds them.


## Type `ShellContext`

The sockets of the shell, in one buffer.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, set by the caller |
| 8 | `capacity` | u64 | Connection entries |
| 16 | `buffer` | u64 | Send buffer bytes of an entry |
| 24 | `stride` | u64 | Bytes of an entry |
| 32 | `listeners` | u64 | Listening sockets |
| 40 | `listen` | 4 u64 | The listening sockets |
| 72 | `started` | u64 | Windows: 1 when `libp2p_shell_init` started Winsock |
| 80 | `poll` | u64 | Offset of the poll array |
| 88 | `entries` | u64 | Offset of the entries |
| 96 | `udps` | u64 | UDP sockets |
| 104 | `udp` | 4 u64 | The UDP sockets, or -1: the socket ID is the index |
| 136 | `accepting` | 16 u64 | Accepted sockets that wait for ADOPT, or -1 |

### Rules

- Entry i belongs to the connection slot index i of the node state.
- One thread at a time uses a context, with its state.


## Type `ShellEntry`

The socket and send buffer of one connection.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `socket` | u64 | The native socket, or -1 |
| 8 | `handle` | u64: a handle ([`Handle`](node.md#type-handle)) | The connection |
| 16 | `state` | u64 | 0 free, 1 connecting, 2 open |
| 24 | `len` | u64 | Bytes waiting in the send buffer |
| 32 | `data` | `buffer` bytes | The send buffer |

### Rules

- An entry is `stride` bytes: 32, then the buffer rounded up to a multiple of 8.


## Type `ListenResult`

The outcome of `libp2p_shell_listen`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `error` | u64 | 0, or the OS error number |
| 8 | `addr` | [`Address`](node.md#type-address) | The bound address |


## Type `BindResult`

The outcome of `libp2p_shell_bind`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `error` | u64 | 0, or the OS error number |
| 8 | `socket` | u64 | The socket ID for DIAL, DATAGRAM and SEND_DATAGRAM |
| 16 | `addr` | [`Address`](node.md#type-address) | The bound address |


## Test vectors

- The shell loop test ([tests/shell/loop.c](../../tests/shell/loop.c)): two nodes over 127.0.0.1 on each of the 7 targets, over TCP and over QUIC on UDP.
- transport-interop of libp2p/test-plans ([tests/interop/](../../tests/interop/)) with the Linux shell: 56 TCP pairs and 24 quic-v1 pairs on x86-64, ARM64 and RISC-V.
- The live test on Ethereum mainnet ([tests/mainnet/](../../tests/mainnet/)) with the macOS ARM64 shell, over TCP and QUIC.

## Results

<!-- CI generates the tick table for each function here. -->

### `libp2p_shell_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_listen`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_bind`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_perform`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_wait`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_close`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_clock`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_sockaddr`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_address`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_layout`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_entry`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_event`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_conn_event`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_drop`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_flush`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_move`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_move_any`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_accept`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_poll_set`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_poll_events`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_fcntl`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  | ✅ |  |
| ARM64 |  |  | ✅ |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_prepare`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  | ✅ |  |
| ARM64 |  |  | ✅ |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_socket`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ | ✅ |  |
| ARM64 |  | ✅ | ✅ |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_accept_one`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ | ✅ |  |
| ARM64 |  | ✅ | ✅ |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_wsa_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ |  |  |
| ARM64 |  | ✅ |  |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_wsa_end`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ |  |  |
| ARM64 |  | ✅ |  |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_nonblock`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ |  |  |
| ARM64 |  | ✅ |  |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_poll`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ |  |  |
| ARM64 |  | ✅ |  |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_udp_read`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `libp2p_shell_udp_socket`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ | ✅ |  |
| ARM64 |  | ✅ | ✅ |  |
| RISC-V |  |  |  |  |

### `libp2p_shell_no_connreset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  | ✅ |  |  |
| ARM64 |  | ✅ |  |  |
| RISC-V |  |  |  |  |
