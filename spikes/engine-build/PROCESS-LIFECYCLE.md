# Source-build process lifecycle

Read-only audit on 2026-10-28 while the guarded engine build was running. No process was signaled. This records the pinned tool's normal shutdown behavior and a limit in the wrapper's independent cleanup verification; it does not report an observed orphan or failed cleanup.

## Observed structure

The owned build launch used process group96107. Its Siso parent96144 remained in that group, while `siso spawn-helper`96146 used group96146. Individual compiler/Python actions beneath the helper also used their own groups. These are ephemeral examples from the owned descendant tree, not reusable process identities or signal targets.

Siso is pinned by Chromium DEPS to build repository revision `c574896b272b40aac6e44c228ee0b471ea7e3d7d`. The installed binary's observed process structure agrees with that revision's implementation.

## Normal cleanup chain

- [spawn_client.go](https://chromium.googlesource.com/build/+/c574896b272b40aac6e44c228ee0b471ea7e3d7d/siso/execute/spawnhelper/spawn_client.go), lines75–77, deliberately sets the helper's own process group so a terminal interrupt or group TERM to Siso cannot kill it before it drains actions. The control socket is created with close-on-exec handling; the parent drops its copy of the helper end after launch.
- [spawn_server.go](https://chromium.googlesource.com/build/+/c574896b272b40aac6e44c228ee0b471ea7e3d7d/siso/execute/spawnhelper/spawn_server.go), lines118–132, treats parent-socket EOF as a shutdown request: cancel every in-flight action, wait for all action goroutines, then return. Parent process death, including SIGKILL, closes its socket; it need not execute a cleanup callback for EOF to occur.
- [proctree_unix.go](https://chromium.googlesource.com/build/+/c574896b272b40aac6e44c228ee0b471ea7e3d7d/siso/execute/localexec/proctree_unix.go), lines44–94, gives each non-console action its own process group. Cancellation sends that group TERM, then KILL after a one-second grace period. Lines99–120 perform a bounded post-wait group drain.
- [localexec_helper.go](https://chromium.googlesource.com/build/+/c574896b272b40aac6e44c228ee0b471ea7e3d7d/siso/execute/localexec/localexec_helper.go), lines47–64, closes the control socket and waits for the helper during normal Siso teardown. [run_unix.go](https://chromium.googlesource.com/build/+/c574896b272b40aac6e44c228ee0b471ea7e3d7d/siso/subcmd/spawnhelper/run_unix.go), lines22–25, also turns a direct helper TERM/interrupt into context cancellation.

Consequently, the separate groups are expected. The pinned normal EOF/cancellation chain supports continuing the current build; their presence alone is not a reason to stop it.

## Wrapper verification limit

`engine.py::terminate_owned` sends signals to the initial launch group and considers cleanup complete when that group disappears. It neither inventories nor independently verifies the helper and action groups. Normal Siso cleanup covers them, but the wrapper's group-only check cannot prove that a failed/stuck helper or an escaped action has stopped.

Siso itself documents that an action descendant calling `setsid()` can escape its group (`proctree_unix.go`, lines22–25), and its drain has a bounded failure path. Therefore “initial group absent” must not be presented as unconditional proof that every descendant exited.

**For the current run, any disk-reserve, error, or cancellation stop requires explicit inspection of the owned helper/action survivors before accepting cleanup or starting another expensive stage.** Record ownership from the live descendant tree before signaling; do not signal stale example IDs or match unrelated processes by executable name alone. Preserve partial build files.

## Bounded future improvement

Track verified descendant process identities and their groups while the command is live and immediately before shutdown. Retain identity information across reparenting, allow the normal Siso drain to finish, then terminate only verified owned survivors with a bounded TERM/KILL sequence. Record unresolved survivors as a cleanup error and block a subsequent launch. Recheck process identity before signaling to avoid PID-reuse mistakes; disappearance of one leader is insufficient evidence that its group is empty.

Meaningful tests should cover a helper in a separate group, separate-group actions that ignore TERM, parent/leader exit before cleanup, descendants that reparent during shutdown, an unrelated sibling process that must survive, simulated PID reuse that must refuse signaling, and a normal EOF-draining helper. Use only disposable synthetic processes. Polling-based tracking also has race limits; document those instead of claiming operating-system containment.
