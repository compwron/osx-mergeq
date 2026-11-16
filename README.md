# MergeQ

Menu bar app that shows the GitHub merge queue for a repo: how many PRs are queued and the expected time to merge.

- Menu bar: `⇄ 3 · 12m`. If one of your PRs is queued, the time is for your PR and gets a `★`. Otherwise it's the time until the whole queue clears.
- Click it for each entry's position, author, state and ETA. Click an entry to open the PR.
- Refreshes every 60s and whenever the menu opens.
- Uses your `gh` CLI login, so no token setup.

## Build and install

```sh
make test      # unit tests
make run       # build and launch from ./build
make install   # copy to ~/Applications and start at login
make uninstall
```

## Pick a repo

Tell it which repo to watch. It uses the queue on the default branch.

```sh
defaults write local.mergeq repo owner/name
```

Then quit and relaunch.
