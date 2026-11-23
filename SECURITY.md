# Security

Lychnion is meant to help people in an emergency. A security problem can
put someone in danger, so please tell us privately first.

## Report a problem

Use GitHub's private reporting:
[Report a vulnerability](https://github.com/lychnion/lychnion/security/advisories/new).
Please do not open a public issue.

No GitHub account? Write to
[hello@lychnion.com](mailto:hello@lychnion.com) instead. Email is not
encrypted, so keep exploit details short and we will move to a private
advisory.

Say what you found, how to reproduce it, and which version or commit you
used. We will answer as soon as we can and tell you before anything is
made public.

## Supported versions

Lychnion is a prototype (0.x) and has no releases yet. Only the `main`
branch gets security fixes.

## In scope

- **Signed data packages and trust keys:** installing a guide, map or
  model that its publisher did not sign; getting a key trusted without
  the user's consent; installing an older version over a newer one.
- **The base on the local network:** a phone or another device on the
  same Wi-Fi that can change current information, read what it should
  not, or crash the base or the phones.
- **Downloads:** files from catalogs, mirrors, USB sticks and phones
  nearby that are used despite a wrong size or SHA-256.
- **The local AI:** a guide or a question that makes the app drop its
  sources or the official safety line, or show text that is not from
  an installed guide.

Out of scope: wrong or outdated content in an official source (open a
normal issue), and problems that need someone who already controls the
device.

## Threat model

The full contract is in [threat-model.md](threat-model.md): what Lychnion
protects, what it leaves to you, and how a report is triaged. The lists
above are a short summary; where they differ, the threat model wins.
