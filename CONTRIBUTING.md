# Contributing

Thank you for helping. A few rules keep the project open for everyone.

## Licence of your contribution

Lychnion's code is under the GNU AGPL version 3 with an app store
exception (see `LICENSE` and `LICENSE-APPSTORE-EXCEPTION.md`). By
contributing, you license your contribution under the same terms,
including the exception. You keep your copyright; add your name to
`AUTHORS`.

## Sign off your commits (DCO)

Every commit needs a `Signed-off-by` line, which says you wrote the change
or have the right to submit it under the project's licence
([Developer Certificate of Origin](https://developercertificate.org/)):

    git commit -s

## Code from elsewhere

Only add third-party code whose licence lets it be combined with the AGPL
and published in app stores (for example MIT, BSD, Apache 2.0). No GPL
code from others: the app store exception cannot cover it.

## Data

Knowledge packages and maps keep the licence of their sources (for example
PDL1.0, CC BY 4.0, ODbL). Every source needs a licence entry in its
package manifest (`packages/*.json` in
[lychnion-data](https://github.com/lychnion/lychnion-data)); the app shows it with each
answer.
