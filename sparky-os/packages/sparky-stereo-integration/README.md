
## Per-user initialization

A pack can declare `initialize` as an absolute executable path in pack.json.
The callback must be idempotent, noninteractive and offline, preserve existing user settings, and fail nonzero with a useful diagnostic on error.
The runner serializes callbacks per user and pack; it does not run them when `program` is missing and it retries on the next event after a failure.
A shared user path unit watches dpkg's status and integrations.d; its service runs callbacks in the logged-in user's session.
Login and explicit actions also synchronize them, so a pack and its program can be installed in either order.
There is no root process that edits home directories and no per-pack service.
Removing a pack removes its declaration, so no later callback runs; user-owned settings and inert lock files remain.
