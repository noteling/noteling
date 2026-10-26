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
- If the gateway's token expires within hours (a sign-in tool keeps it renewed on disk), let a script make it instead
  of having everyone paste it again. See the next section.
- While linked, these win over the person's own Claude settings. The top of Settings' **Claude** section says where
  questions, screenshots and the text Noteling reads go, and the fields you set are greyed out. Nothing personal (their
  own key or headers) is sent to your gateway unless a header asks for it by name. Unlinking your tools gives them their
  own settings back.

### A token that keeps changing: secretScripts

`secretScripts` names the pack script that makes a secret. Noteling runs it right before a request needs the secret,
so nobody types a token that expires the same day:

```json
{"claude": {"baseURL": "https://llm-gateway.example.com",
            "headers": {"Authorization": "$GATEWAY_TOKEN"},
            "secretScripts": {"GATEWAY_TOKEN": "gateway-auth/token"}}}
```

`gateway-auth/token` is `gateway-auth/scripts/token.py` in your repository. Its `run()` takes no arguments and returns
the header's whole value as text (`"Bearer eyJ…"`, since only a value that is exactly `$NAME` is filled in), or
`{"value": "Bearer eyJ…", "ttl": 600}` to say how many seconds Noteling may keep it.

```python
import pathlib

def run():
    """Reads the token our sign-in tool keeps renewed."""
    path = pathlib.Path.home() / ".gateway" / "token"
    if not path.exists():
        raise RuntimeError("Sign in first: run gateway-login")
    return {"value": "Bearer " + path.read_text().strip(), "ttl": 300}
```

- Noteling keeps the value for 60 seconds unless `ttl` says otherwise, an hour at most, and only in memory: never on
  disk or in the log. If the gateway turns a request down (401 or 403), it runs the script again and sends once more.
- The script runs like the pack's other scripts, with the secrets its pack `requires`, and stops after 15 seconds. It
  is never offered to Claude as a tool.
- When it fails, a saved secret of the same name is used if there is one. Without one, the question ends with what the
  script said ("Sign in first: run gateway-login"). Settings' **Claude** section shows the same line, and asks for no
  value for a secret that has a script.
- A person can name their own in config.json as `apiSecretScripts`. The team's entry wins for the same name.
- `NOTELING_TOOLS_REPO_TOKEN` can't come from a script, and a setup file never carries one: the script lives in your
  repository.

To try it in Terminal, `/Applications/Noteling.app/Contents/MacOS/Noteling --ask "hello"` makes the token the way chat
does, and prints what went wrong if it can't.

## The words your people use: verbs

Every message asks for one of three things: to understand (**Explain**), to be able to do it next time (**Teach me**),
or to have it done (**Do it for me**). Those are the tabs under a how-to answer and the verbs on the line over the chat
input. If your people say it differently, in their jargon or their language, `verbs` renames the three and gives
Noteling examples of how they put each one:

```json
{"verbs": {"teach": "Show me how", "act": "Just do it",
           "examples": {"teach": ["walk me through it", "带我走一遍"], "act": ["sort it out", "帮我搞定"]}}}
```

A word you leave out keeps its English. The three must differ, since a tab means one thing, and each is at most 24
characters so it fits on a tab. Examples (up to 8 per verb) only illustrate the verb for the model; nothing matches on
them, and people are never required to use them. The words apply on every linked Mac and are never written into
anyone's own settings.

## Behind a proxy

Scripts get the Mac's proxy and trusted certificates as `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` and `SSL_CERT_FILE`,
which Python's `urllib` uses as they are. Nothing to set up.

## Next

- [Testing](testing.md): try everything before you push.
- [Getting started](../use/getting-started.md): the page to send your team.
