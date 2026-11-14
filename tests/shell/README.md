# Shell loop test

`loop.c` runs two nodes in one process, connected over 127.0.0.1 through the shell of the target. It uses standard C only, so the same file runs on Linux, macOS and Windows. It is test code; the library itself is pure assembly.

| Round | Muxer | Keys |
|---|---|---|
| 1 | yamux | A Ed25519, B secp256k1 |
| 2 | mplex | A secp256k1, B Ed25519 |

Each round:

- A listens on 127.0.0.1, port 0; B dials it with the peer ID of A.
- Both join a topic.
- B opens an application stream, writes 256 KiB, and closes its side; A echoes the bytes, then closes; B checks every byte and the end of the stream.
- A publishes one message; B gets it, gives its ID, and accepts it.
- B disconnects; both see the peer go.

It prints "FUNCTION <name> PASS" for each shell function when both rounds pass, and FAIL with the step that failed otherwise. `TRACE=1` prints every action.

[platform/linux/build.sh](../../platform/linux/build.sh) and [platform/windows/build.sh](../../platform/windows/build.sh) build it; [platform/macos/link-runner.sh](../../platform/macos/link-runner.sh) links it on a Mac. [tests/runner/docker.sh](../runner/docker.sh), [tests/runner/macos.sh](../runner/macos.sh) and CI run it.
