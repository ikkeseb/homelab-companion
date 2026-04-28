# YAML 1.1 boolean keyword trap in string-enum config

YAML 1.1 silently coerces unquoted `off`, `no`, `n`, `false`,
`on`, `yes`, `y`, `true` (and case variants) to booleans before
schema validation runs. When a schema expects a string enum and
the value matches one of those tokens, you get a "Configuration
error" with no field name, no parse-vs-schema distinction, and
no clue that the parser already silently changed your value's
type. The fix is one character per occurrence: quote it.

## Symptom

The classic surface presentations:

- **Home Assistant Lovelace card** — "Configuration error", no
  field name, no line number. `check_config` returns `valid`
  because the YAML is syntactically valid; the error happens
  later when the card schema rejects a bool where it wanted a
  string enum.
- **GitHub Actions** — `if: inputs.foo == no` evaluates the
  wrong way because `no` parses as bool `false`, not the string
  `"no"`.
- **Ansible** — group_vars or host_vars values intended as
  string flags silently become bool, breaking conditionals
  downstream.
- **Docker Compose v1** — environment values for apps that read
  string enums from `os.environ`.

The user sees an error from the consumer ("invalid config"),
not from the parser ("I converted `off` to `False`"). That
asymmetry is the whole trap.

## Root cause

YAML 1.1 (PyYAML, libyaml, and everything built on them) treats
a fixed set of unquoted tokens as boolean or null literals
**during parse**, before the schema runs:

```
→ bool False:   off  Off  OFF  no   No   NO   n  N  false  False  FALSE
→ bool True:    on   On   ON   yes  Yes  YES  y  Y  true   True   TRUE
→ NoneType:     null  Null  NULL  ~
```

(Note: lowercase `none` is **not** in the list — it parses as
the literal string `"none"`. Subtle but useful.)

When the schema validator sees the parsed structure, the value
type is already wrong. The error message comes out of the
schema layer, which has no idea that the original source said
`mode: off` — it just sees `mode: False`. From the user's seat,
the YAML "looks fine" because every YAML primer they've ever
read uses unquoted booleans for boolean fields.

YAML 1.2 fixed this by removing the implicit conversions for
`yes`/`no`/`on`/`off`. Most of the homelab/DevOps ecosystem is
still on YAML 1.1: Home Assistant, Ansible, GitHub Actions,
Docker Compose v1.

### Diagnosis

Find candidates with grep:

```bash
grep -rEn '^\s*[a-z_]+:\s*(off|on|no|yes|y|n|true|false|null)\s*$' \
    configs/
```

Then for any flagged line, check the consumer's schema. If the
field expects a string enum (e.g. `mode: off | on | auto`),
the value must be quoted. If the field genuinely is a boolean,
unquoted is fine.

To confirm a specific file's parse types:

```bash
python3 -c '
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))
print(yaml.dump(data, default_flow_style=False))' my-config.yaml
```

Compare the dumped output against the source. If `mode: off`
came back as `mode: false`, the conversion happened.

## Fix

Quote any string-enum value whose token matches a YAML 1.1
boolean keyword. Either single or double quotes work:

```yaml
# Safe (string preserved)
mode: 'off'
state: "on"
visible: 'no'
display: 'yes'

# Unsafe (silently parsed as bool)
mode: off
state: on
visible: no
display: yes
```

The cost of unnecessary quoting is one character. The cost of
the trap firing is a 30-minute debug session staring at a
schema validator that won't tell you the parser already lied.
Default to quoting any value that *could* be ambiguous.

## Why LLMs miss this

When asked *"why does this YAML fail"*, models inspect the
schema, not the parse. They reach for *"check the schema"*,
*"verify the field name"*, *"compare against the upstream
example"* — surface-level config debugging. They rarely
volunteer the YAML 1.1 conversion as a hypothesis, because
it's hidden machinery the human eye doesn't parse and most
training-data answers don't reach for it either.

ChatGPT in particular has a habit of *"fixing"* YAML by
**removing** quotes around `'off'` or `'no'` because it "looks
cleaner" — re-introducing the bug. This is a bidirectional
miss: models don't suggest the right fix unprompted, and they
will undo the right fix when given the chance.

The discernment models lack here is *YAML has hidden
conversions before the schema sees the data*. The right move,
when a YAML config fails with an unhelpful schema error, is to
inspect the parse output (via `python -c "yaml.safe_load(...)"`
or `yq`) **before** suspecting the schema. If the parsed type
doesn't match the source token type, the conversion is the
bug. Schemas that do their job report what they got — they
can't report what was lost in translation before they got it.

A useful prompt to deflect the surface miss: *"before checking
the schema, parse this YAML with PyYAML and dump the result —
did `mode: off` come back as `False`?"* That routes the model
straight to the parse-coercion check.

## See also

- [sync-before-write](sync-before-write.md) — sibling in the
  "the surface error is misleading; the cause lives one layer
  up" shape. There it's call ordering; here it's parse-vs-
  schema.
- [ufw-docker bridge drop](ufw-docker-bridge-drop.md) — also
  about the surface lying. There `iptables -L` says "rules
  enforced"; here the schema validator says "type mismatch".
  In both cases, asking the data layer directly resolves it.
