# Bijdragen

## Commitberichten

`<type>[(scope)][!]: <beschrijving>` — bijvoorbeeld `feat(app): hoogteprofiel` of
`fix(importer): verouderde edges terug op onbekend`. De CI weigert een pull request
met een onderwerpregel die hier niet aan voldoet, omdat `release.yml` de
versiesprong en de release-notes eruit afleidt: `fix` → patch, `feat` → minor,
`!` of `BREAKING CHANGE` → major.

Gangbare scopes: `app`, `chart`, `importer`, `ci`.
