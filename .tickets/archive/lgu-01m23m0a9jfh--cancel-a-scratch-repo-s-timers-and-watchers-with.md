---
id: lgu-01m23m0a9jfh
title: Cancel a scratch repo's timers and watchers with the repo
status: closed
type: bug
priority: 2
mode: afk
created: '2026-09-09T17:38:44.146858174Z'
updated: '2026-09-09T17:39:12.910738016Z'
closed: '2026-09-09T17:39:12.910738016Z'
acceptance:
- title: legu-test--with-repo cancels the root's refresh timer and removes its store watchers before deleting the directory
  done: false
- title: 'A test pins the invariant: nothing is left in legu--refresh-timers or legu--watchers for a finished repo'
  done: false
- title: 25 consecutive full runs of emacs/legu-tests.el are green
  done: false
---

## Description

`legu-test--with-repo` deletes its scratch repository but leaves whatever the
body armed against it: the debounce timer in `legu--refresh-timers` and the
`.review` watchers in `legu--watchers`. Neither table is let-bound by the
macro, and neither is torn down.

An armed timer that outlives its directory fires `legu--snapshot-start` into a
path that is gone. Emacs reports the failure through `message`, and
`legu-test-version-handshake-happens-on-the-first-cli-run` stubs `message` to
count what the handshake said. It sees two messages instead of one and fails,
in whichever run the timing lines up. Roughly one run in five.

Found on the first run of the suite after emacs reached the sandbox image. It
predates the babashka.cli work: nothing in it depends on how legu parses a
command line.

The teardown must drop the watchers before it cancels the timer. A live watch
re-arms the timer the moment anything pumps the event loop, and the teardown's
own drain wait pumps it.

## Notes

**2026-09-09T17:39:12.910738016Z**

legu-test--with-repo now removes the root's .review watchers and cancels its
debounce timer before deleting the directory. Order matters: a live watch
re-arms the timer as soon as anything pumps the event loop, and the teardown's
own drain wait pumps it, so cancelling first left a fresh timer behind.

legu-test-integration-a-finished-repo-leaves-nothing-armed pins both tables
empty for a finished repo. It fails on the old teardown.

25 consecutive full runs green, and 10 more with evil and goto-chg on the load
path (145/145, no group skipped). The old teardown flaked about one run in
five.
