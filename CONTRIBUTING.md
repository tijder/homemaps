# Contributing

## Commit messages

`<type>[(scope)][!]: <description>` — for example `feat(app): elevation profile` or
`fix(importer): stale edges back to unknown`. CI rejects a pull request
whose subject line doesn't follow this, because `release.yml` derives the
version bump and the release notes from it: `fix` → patch, `feat` → minor,
`!` or `BREAKING CHANGE` → major.

Common scopes: `app`, `chart`, `importer`, `website`, `ci`.
