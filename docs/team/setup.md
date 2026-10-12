# Setting up your team

Everything a person needs to use your tools fits in one file they double-click. This page covers the token, that setup
file, secrets, and how Noteling reaches Claude through your company's gateway.

## The repository and its token

Noteling reads your repository through GitHub's API: no git, nothing to install. It works with github.com, GitHub
Enterprise Cloud and GitHub Enterprise Server. The address is the repository's web address, such as
`https://github.example.com/team/tools`.

Make a **fine-grained token** for that one repository, with **Contents: Read-only** and an expiry. Everyone on your team
can share it: it can read your tools and nothing else. When it expires, the line under the token says Noteling couldn't
update, and it keeps using the copy it has; send people a new setup file.

Noteling follows the `main` branch by default. It checks when the Morning folder opens (at most once a minute) and every
10 minutes, so a push reaches every linked Mac within 10 minutes, or as soon as someone opens the folder. **Update now**
in Settings checks right away.

## The setup file

```json
{"noteling_setup": 1,
 "name": "Orders team",
 "tools_repo": {"url": "https://github.example.com/team/tools", "token": "github_pat_…"},
 "secrets": {"ORDERS_API_KEY": "…"}}
```

Save it as `Orders team.notelingsetup` and share it inside your team, in a direct message or your team's file share.
Double-clicking it opens Noteling, which says what it will do. On **Set up**, it links the repository and saves the
secrets in the person's Keychain. People can also open one from **Settings → Team tools from GitHub → Import setup
file…**.

- `tools_repo` takes `url`, `token`, and `branch` if it isn't `main`.
- `secrets` holds up to 20 values, under names like `ORDERS_API_KEY` (capital letters, digits and `_`). Put only values
  everyone shares here; each person enters their own in Settings.
- A setup file sets nothing else, and is never run.

**Anyone with the file can read the token.** Keep the token read-only, for this one repository, with an expiry. Never
commit a setup file: the [template repository](https://github.com/noteling/team-tools-template)'s `.gitignore` keeps them
out.

## Secrets

A pack's `requires:` and a job's `requires` name the secrets a script needs. Each one gets a field in **Settings → Tool
packs**, saying which pack or job uses it, and Jobs says "Needs … in Settings" on a job that's missing one. Noteling keeps
them in the person's Keychain, and hands each script only the ones it names, as environment variables.

In Noteling 0.7.0, a secret that only a job names has no field in Settings yet: bring it in the setup file, or name it in
a pack's `requires` too. Later versions list it.

## Your company's Claude gateway: noteling.json

A `noteling.json` at the top of your repository sets how every linked Mac reaches Claude:

```json
{"claude": {"baseURL": "https://llm-gateway.example.com/anthropic",
            "headers": {"X-Consumer-Id": "orders-team", "X-Api-Key": "$GATEWAY_KEY"},
            "model": "claude-opus-5", "effort": "medium"}}
```

- `baseURL` is everything before `/v1/messages`, which Noteling adds. It must be `https`. The gateway must accept
  Anthropic's Messages API as it is.
- A header value written exactly `$NAME` is a secret each person enters once in **Settings → Tool packs**. Anything else
  is sent as written. `Host`, `Content-Length`, `Content-Type`, `Connection`, `Transfer-Encoding` and
  `anthropic-version` can't be set.
- `model` and `effort` (`low`, `medium`, `high`, `xhigh` or `max`) are optional.
- While linked, these win over the person's own Claude settings. The top of Settings' **Claude** section says where
  questions, screenshots and the text Noteling reads go, and the fields you set are greyed out. Nothing personal (their
  own key or headers) is sent to your gateway unless a header asks for it by name. Unlinking your tools gives them their
  own settings back.

## Behind a proxy

Scripts get the Mac's proxy and trusted certificates as `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` and `SSL_CERT_FILE`,
which Python's `urllib` uses as they are. Nothing to set up.

## Next

- [Testing](testing.md): try everything before you push.
- [Getting started](../use/getting-started.md): the page to send your team.
