# Code Review: remote-command-argv

Date: 2026-08-20
Review rounds: 2 (triangulate, standalone Phase 3) + one external review

## Scope

Fix for `smart-ssh <host> <command>` failing with
`hostname contains invalid characters`. The parser folded the remote command
into `ssh_options`, and all three exec sites built `ssh <options> <hostname>`,
so the command preceded the destination and ssh read its first word as the
host.

## Changes from Previous Round

Initial review.

## Method

Three expert sub-agents (functionality / security / testing) reviewed the
working-tree diff in parallel. Ollama was unavailable, so no seed findings were
generated and all three fell back to full-diff review; the merge below is
manual.

## Functionality Findings

- **F1 (Critical, fixed)** — `_ssh_option_takes_value` tested the argument's
  *last character*, so an attached value ending in a value-taking letter
  (`-oUser=bob`, `-i/k/sub`, `-luserb`) was read as "option plus separate
  value" and swallowed the hostname. `smart-ssh -oUser=bob myhost uptime`
  resolved `Target: uptime` — credential selection ran against the wrong host.
  A regression introduced by this change. Fixed by testing the option letter's
  *position*: a bare value-taking option, or a bundle of boolean flags ending
  in one.
- **F2 (Major, fixed)** — `-Q` absent from the arity set. ssh(1) has a second
  SYNOPSIS line (`ssh [-Q query_option]`) that the derivation missed.
  Independently reported by the security expert. Fixed; the comment now records
  that both synopsis forms must be consulted.
- **F3 (Major, NOT fixed — needs a spec decision)** — options after the
  hostname are hoisted before it, so `smart-ssh myhost -- --version` yields
  `ssh --version myhost`, and `myhost --help` / `myhost -d` are captured by
  smart-ssh's own flags. Verified pre-existing at HEAD. Not fixed because the
  two remedies conflict: `usage()` documents `hostname -p 2222` as supported,
  which "stop parsing at the hostname" would break. See Resolution Status.
- **F4 (Minor, fixed)** — an empty-string hostname was indistinguishable from
  "not yet set", so `smart-ssh "" myhost uptime` silently promoted `myhost`.
  Fixed with an out-of-band `hostname_set` flag; now exits 1.

## Security Findings

No Critical or Major findings.

The `-F` stripping invariant — the caller's `-F` must never reach the run
command, or it would replace the generated temp config and discard its
`IdentitiesOnly` / `IdentityAgent none` restrictions — held across all eight
argument shapes tested in this round (`-F path`, `-Fpath`, `-vF path`, each
before and after the hostname, and through `--`).

**The stated reason was wrong, and Round 2 disproved it.** This round argued the
mechanism was structural: "anything after the hostname is past ssh's option
parsing." It is not. `ssh` RESUMES option parsing after the destination and
continues until the first non-option word:

```
$ ssh -G -F pa.cfg probe -F pb.cfg
hostname 198.51.100.99      # pb.cfg won; pa.cfg's value discarded
```

The Round 1 conclusion happened to hold only because the parser of the time
never placed such an argument after the hostname. Round 2's grammar change did,
which turned the false premise into a live credential-pinning bypass — see
Round 2 finding S1.

- **S1 (Minor)** — same `-Q` gap as F2; fixed.
- **S2 (Minor, NOT fixed)** — a caller `-F` placed after the hostname is
  correctly dropped on the away/OIDC paths but without any warning, so a user
  may believe their config selected the identity. Pre-existing.
- **S3 (Minor, NOT fixed)** — the arity-swallow block is duplicated across the
  `-*` and `--` branches. Both call the same helper, so the class cannot
  diverge; only the surrounding three lines are copied.

`SSH_REMOTE_COMMAND` is a global but is reset on `main` entry, and `main` runs
once per process, so no value can leak across the home/away/OIDC paths. The
script sets neither `-u` nor `-e`, so empty-array expansion on bash 3.2 is not
a hazard here.

## Testing Findings

- **T1 (Critical, fixed)** — `setup` set `SECURITY_KEY_PATH=/tmp/test_key`,
  outside the tree `teardown` reclaims. Tests 140-144 passed only because an
  earlier test littered that path; on a clean `/tmp` they failed. Fixed at the
  source (the key now lives in `TEST_CONFIG_DIR`), which exposed two
  pre-existing tests (71, 74) that had the same hidden dependency — both now
  create their own fixture.
- **T2 (Critical, fixed)** — the regex assertions used `.*` between tokens and
  matched the exact wrong ordering the fix repairs. Replaced with
  `_assert_exec_line`, which extracts the executed argv, normalizes only the
  variable temp-config path, and compares exactly.
- **T3 (Major, fixed)** — the OIDC exec site had no remote-command coverage
  despite receiving the identical edit. Test added.
- **T4 (Major, fixed)** — the 22-letter arity class was tested on ~6 members.
  Added a table-driven test over the forwarding options (`-L -R -D -J -W`),
  whose values most resemble a destination.
- **T5 (Minor, partially addressed)** — remaining untested shapes: a lone `--`,
  a remote command whose own words start with `-`, and quoted/spaced commands.
  The dry-run line renders the command with `${SSH_REMOTE_COMMAND[*]}`, which
  flattens quoting the real `"${...[@]}"` exec preserves, so the printed
  command can misreport a quoted argument. Not fixed; display-only.

The testing expert also reported that its own snapshot handling may have
clobbered concurrent edits. Verified afterwards: the only delta from the
pre-review snapshot was the intended `hostname_set` change, except for the
final `[ -z "$hostname" ]` guard, which had reverted and was restored.

## Verification

- `bats tests/test_smart_ssh.bats` — 151/151 pass, on a clean `/tmp`, twice in
  succession, and order-independent when run as a filtered subset.
- Red-proved against the true pre-fix script (`git show HEAD:smart-ssh`):
  11 of the 12 new tests fail there and pass on the fix. Test 142 passes both
  ways by design — it guards the F1 regression introduced during the fix, not
  the original bug.
- Mutation-proved the arity logic: reverting to tail-matching reddens the two
  attached-value tests; removing `Q` reddens only the `-Q` test.
- `shellcheck -e SC2155,SC2129,SC2181,SC2029 smart-ssh` — clean.
- End to end: `smart-ssh vps-tk1 'uptime'` now resolves `Target: vps-tk1` and
  builds `ssh vps-tk1 uptime`.

## Resolution Status

### F1 Critical — attached option value swallows the hostname
- Action: rewrote `_ssh_option_takes_value` to decide on option-letter
  position rather than the argument's trailing byte
- Modified: `smart-ssh:1626-1655`
- Tests: `tests/test_smart_ssh.bats` — "does not let an attached option value
  swallow the hostname", "treats an attached path value as self-contained"

### F2 / S1 Major — `-Q` missing from the arity set
- Action: added `Q` to `_SSH_VALUE_OPTS`; comment now records that ssh(1) has
  two SYNOPSIS forms and both must be consulted
- Modified: `smart-ssh:1639`
- Test: "smart-ssh treats -Q as taking a value"

### F4 Minor — empty hostname silently dropped
- Action: added `hostname_set` to track presence out-of-band; an explicitly
  empty hostname now exits 1
- Modified: `smart-ssh:1913`, `:1988`, `:1966`, `:2005`
- Test: "smart-ssh rejects an empty hostname instead of using the next argument"

### T1 Critical — test fixture leaked outside the reclaimed tree
- Action: `SECURITY_KEY_PATH` moved into `TEST_CONFIG_DIR`; tests 71 and 74,
  which had silently depended on the leaked file, now create their own
- Modified: `tests/test_smart_ssh.bats:21`, `:1404`, `:1464`

### T2 Critical — assertions matched the wrong argv ordering
- Action: added `_assert_exec_line` and converted all 10 argv assertions to
  exact comparison
- Modified: `tests/test_smart_ssh.bats:82-95` and the new tests

### T3 Major — OIDC exec site uncovered
- Action: added "OIDC path puts a remote command after the hostname", using the
  real cert-pair setup the other OIDC tests use

### T4 Major — arity class under-tested
- Action: added "smart-ssh treats forwarding options as taking a value" over
  `-L -R -D -J -W`

### F3 Major — post-hostname options hoisted before the destination — FIXED
- Status: fixed, after the maintainer chose option (a). The tool has a single
  user, so the compatibility argument for keeping the old ordering did not
  apply.
- Action: the hostname now ends option parsing, exactly as it does for ssh
  itself. The guard runs before the `case`, not inside its `-*)` arm — placing
  it there was not enough, because smart-ssh's own `--help` / `-d` / `--` arms
  come earlier in the `case` and captured `smart-ssh host --help` before the
  guard was ever reached.
- Modified: `smart-ssh:1921-1931` (guard), `smart-ssh:265-296` (usage text)
- Also updated, because they encoded the old ordering:
  - `completions/_smart-ssh`, `completions/smart-ssh.bash` — both offered SSH
    options after the hostname, a position where they would now be sent to the
    remote shell. They complete command names there instead.
  - `README.md`, `README.ja.md` — six examples each used `host -v` style
    ordering; remote-command examples added.
  - `tests/test_smart_ssh.bats` — 14 invocations passed `-F`/`-o` after the
    hostname. Verified these were not stale: the shape appears in a regression
    test whose comment reads "end to end, the shape from the report", from
    commit edfa648 ("allow connecting to DNS-resolvable hosts not in ssh
    config"). Moving the option ahead of the hostname preserves what each test
    asserts; none of the assertions were weakened.
- Verified: `smart-ssh host --help`, `smart-ssh host -d`, and
  `smart-ssh host -- --version` now all reach the remote instead of being
  captured locally or hoisted ahead of the destination.
- Note: `bash 3.2` on macOS has no `;;&`, so the guard is a plain `if` before
  the `case` rather than a fall-through arm.

### S2 Minor — dropped `-F` not reported — DEFERRED
- Status: not fixed; pre-existing, and the drop itself is the security-correct
  behavior. Adding a warning is a UX improvement that should be paired with a
  test asserting the home path (which legitimately honours `-F`) stays silent.
- Worst case: a user misreads which config, and therefore which identity, was
  used. No wrong credential is offered.
- Likelihood: low.
- Cost to fix: small; deferred only to keep this change focused on the argv bug.

### S3 Minor — arity swallow duplicated across two branches — DEFERRED
- Status: not fixed. Both sites call the same helper, so the arity *class*
  cannot diverge; only the three-line swallow is duplicated.
- Worst case: a future edit to one branch and not the other.
- Likelihood: low.
- Cost to fix: small; deferred as unrelated cleanup.

### T5 Minor — dry-run flattens quoted remote commands — DEFERRED
- Status: not fixed. Display-only: the dry-run line uses `${...[*]}` while the
  real exec uses `"${...[@]}"`, so a quoted argument prints unquoted but runs
  correctly.
- Worst case: a user copies the printed command and gets different splitting.
- Likelihood: low.
- Cost to fix: small.

---

# Round 2

Date: 2026-08-20
Trigger: the maintainer chose option (a) for Round 1's deferred F3 — the
hostname ends option parsing, exactly as it does for ssh itself. Reviewed by the
same three experts plus an independent external review.

## Scope of the change reviewed

- `smart-ssh` — a guard before the argument `case` routes everything after the
  destination into `SSH_REMOTE_COMMAND`.
- 14 test invocations that passed `-F` / `-o` after the hostname were rewritten
  to pass them before it.
- Both completions, both READMEs and `usage()` updated to the new grammar.

## Findings

### S1 (Critical, fixed) — post-hostname options defeated credential pinning

The premise Round 1 relied on is false: ssh resumes option parsing after the
destination. Round 2's grammar routed caller options there verbatim, so on the
away and OIDC paths:

```
$ smart-ssh --dry-run --security-key myhost -F leak.cfg
ssh -F <temp> myhost -F leak.cfg

$ ssh -G -F <temp> myhost -F leak.cfg
identitiesonly no
identityfile .../ondisk_key      # security key displaced
```

An ordinary on-disk key would be offered on an untrusted network — precisely
what the temporary config exists to prevent. This was a regression against HEAD,
which stripped it.

**Fix**: `--` immediately before the destination at all three exec sites, so
ssh's own parser adjudicates rather than smart-ssh's model of it (R47 — climb to
the interpreter's semantics instead of reasoning about notation). Nothing is
lost: the temp config is generated from `ssh -G` output that already merged the
caller's `-F`.

Verified by execution: with `--`, `ssh -G -F <temp> -- myhost -F leak.cfg`
resolves to `identitiesonly yes` / `identityagent none` / the security key.
Allow side preserved: `-- myhost uptime` still resolves correctly, so legitimate
remote commands keep working.

### S2 (Critical, fixed) — `--` branch hoisted post-hostname options, enabling local execution

The `--` arm's inner loop tested `[[ "$1" == -* ]]` BEFORE `hostname_set`, so a
dash-argument after the destination was appended to `ssh_options` and re-emitted
ahead of the hostname:

```
$ smart-ssh --dry-run --security-key -- myhost '-oProxyCommand=sh -c id' uptime
ssh -F <temp> -oProxyCommand=sh -c id myhost uptime
```

`ProxyCommand` executes on the LOCAL machine, so a wrapper of the form
`smart-ssh -- "$host" "${cmd[@]}"` turned remote-command text into local command
execution. The boundary also moved with the spelling — `--` or bare — which is a
boundary the caller picks.

Reported independently by the external review and by both the functionality and
security experts (R48: two adjudicators deciding one predicate in different
orders).

**Fix**: hoist the `hostname_set` test above the dash test so both loops share
one grammar. Allow side preserved: `-- -v myhost uptime` still yields
`ssh -v -- myhost uptime`.

### S3 (Major, fixed) — display flattened quoting and emitted terminal escapes

The dry-run and debug lines rendered the argv with `${array[*]}` and printed it
through `echo -e`. Two consequences, both reproduced:

- `myhost echo 'a  b'` printed as `... echo a  b` — one argument shown as two,
  so an operator auditing a destructive command read a different command than
  the one that would run. The comment claiming the dry run "cannot describe a
  command different from the one that would run" was an R49 overstatement.
- `myhost 'x\033[31mRED'` emitted a real ESC byte into the terminal.

**Fix (first attempt, incomplete)**: a `render_argv` helper using `printf '%q'`,
applied at all three render sites.

**S4 (Major, fixed) — %q alone was not enough.** A follow-up external review
caught that the print helpers still used `echo -e`, which expands backslash
sequences in the message as well as the colour. `%q` renders a RAW control byte
as its backslash spelling, so `echo -e` turned it straight back into the byte:

```
$ smart-ssh --dry-run --security-key myhost $'x\nFORGED'
... -- myhost $'x
FORGED'                       # a real newline — a forged log line
```

BEL, CR and ESC behaved the same way. The helpers now use
`printf '%b%s%b'` — the colour expands, the message does not.

The test written for S3 did not catch this because it passed the two-character
text `'\033[31mRED'`, which `%q` neutralises on its own; the raw-byte case is
the half that was broken. It now passes real newline, BEL, CR and ESC bytes and
asserts none survives into the rendered line. This is the round's clearest
instance of a fixture that tested the easy direction of its own property.

### D1 (Major, fixed) — docs and completions still taught the old grammar, and
the explanation was wrong

`usage()` and both READMEs said the hostname ends option parsing "as with ssh".
It does not — ssh resumes parsing after the destination, which is the reason the
exec sites pass `--` at all. Corrected to say smart-ssh treats the hostname as
the boundary and inserts `--` for ssh. The same false claim in Round 1's
reasoning is what produced S1, so it was worth removing from the docs too.


- `usage()` and both READMEs documented `-- hostname -v` as the way to pass ssh
  options — the one shape the new grammar excludes. Corrected to `-- -v hostname`,
  and the "remaining args are SSH options" line reworded, since `--` now ends
  smart-ssh's own option parsing rather than making everything after it an ssh
  option. Every `usage()` example was then executed under `--dry-run` and matches
  its stated intent.
- Both completion files offered SSH options after the hostname — a position that
  is now remote-command territory. They complete command names there instead.

## Findings deferred (with one fixed late — D6)

### D2 (Major) — completions' `--` branch still returns before the new logic
`completions/smart-ssh.bash:36-55`, `completions/_smart-ssh:63-84`. Both files'
pre-existing `--` branch returns unconditionally, ahead of the new
remote-command branch, so `smart-ssh -- myhost <TAB>` still offers ssh options.
The bash file's `case "${prev}"` arms for `-i|-F` also fire without a position
test, so `smart-ssh myhost -F <TAB>` offers filenames.
- Worst case: a wrong completion suggestion. No effect on what is executed —
  completion never feeds the exec path.
- Likelihood: moderate for anyone using `--` with tab completion.
- Cost to fix: small, but it wants a completion test harness the repo does not
  have (bats can drive `COMP_WORDS`/`COMP_CWORD` with no new dependency).
- Deferred because completion accuracy is currently best-effort — untested and
  unlinted in CI. Fixing it blind would repeat the mistake this round found.

### D3 (Minor) — `hostname_idx` in bash completion has no arity awareness
`completions/smart-ssh.bash:30` treats the first non-dash word as the hostname,
so `smart-ssh -p 2222 <TAB>` reads `2222` as the destination (RT9 twin drift
against `_ssh_option_takes_value`). Same disposition as D2.

### D4 (Minor) — zsh completion's `ssh_options` array is now dead
`completions/_smart-ssh:12,26-43`. Only consumed by the `_arguments` call this
round replaced. Harmless; folded into whatever fixes D2.

### D5 (Minor) — inconsistent exit codes for "no usable hostname"
Measured, not assumed:

| invocation | exit |
|---|---|
| `smart-ssh` (no arguments) | 0 (usage) |
| `smart-ssh --` | 1 |
| `smart-ssh --invalid-option` | 1 |
| `smart-ssh "" myhost` | 0 (usage) |
| `smart-ssh --dry-run --security-key "" myhost uptime` | 1 |

A wrapper cannot detect the failure reliably. Pre-existing and outside this
round's diff; normalizing it changes the CLI contract, so it is the maintainer's
call.

### D6 (Major, fixed) — an empty first argument bypassed the parser entirely
`smart-ssh:2307`. The top-level dispatch reads `--help|-h|"")` , so when the
FIRST argument is the empty string the script prints usage and exits 0 without
ever entering `main` — the `hostname_set` guard added in Round 1 for exactly this
case never runs. `smart-ssh "" myhost uptime` therefore exits 0 silently instead
of erroring, while `smart-ssh --dry-run --security-key "" myhost uptime` (any
leading flag) reaches `main` and correctly errors.

The Round 1 test passes because it uses the flagged form. The unflagged form —
the one a wrapper with an unset `$1` actually produces — is uncovered.

- Worst case: a script whose hostname variable is unset silently succeeds
  instead of failing. No wrong host is contacted (nothing is executed), but the
  caller cannot tell.
- Likelihood: low but not contrived — an unset variable in a wrapper is the
  canonical way to produce it.
**Fixed.** The no-argument case is now decided by `$# -eq 0` before the `case`,
and `""` was dropped from the `--help|-h` arm, so an empty first argument falls
through to `main`'s existing rejection. Verified: `smart-ssh "" myhost uptime`
exits 1 with "Please specify a hostname"; bare `smart-ssh` still prints usage and
exits 0; `--help` unchanged. Both sides are pinned by tests, and restoring `""`
to the arm reddens exactly those two.

## Verification

- `bats tests/test_smart_ssh.bats` — 161/161 pass, clean `/tmp`, no fixture leak.
- Mutation-proved, each reddening only its own guards:
  - removing `--` from the exec sites → 15 tests red
  - reverting the `--` branch predicate order → tests 145, 146, 147 red
  - reverting `render_argv` to `${array[*]}` → the two display tests red
  - restoring `""` to the `--help|-h` dispatch arm → the two empty-argument
    tests red
  - reverting `print_info`/`print_debug` to `echo -e` → the control-byte test red
  - swapping `render_argv_redacted` back to `render_argv` → the debug-log test red
- `shellcheck -e SC2155,SC2129,SC2181,SC2029 smart-ssh` — clean.
- `git diff --check` — clean.
- `ssh -G` used as the authority for the credential-pinning assertions rather
  than argv text, because an argv-substring assertion passed throughout the S1
  regression.

### S5 (Minor, fixed) — the remote command was written to the debug log verbatim

Raised by the final external review. A remote command routinely carries a token
or a password in an argument, and the debug log goes wherever the operator
redirected it and outlives the session. The debug lines now report the command
by argument count.

The dry run deliberately still prints it in full — showing exactly what would
run is the purpose of that flag, and it goes to the terminal on request rather
than into a log. Both directions are pinned by tests, so redacting the dry run
would fail just as failing to redact the log does.

## Process note

Three review agents ran in parallel against the working tree while fixes were
being applied. One agent's edit-and-restore cycle silently reverted the S2 fix,
which is why an external review saw it as unfixed after it had been applied.
Later rounds pinned a checksummed snapshot before dispatching agents, and every
agent was instructed to snapshot its own copy rather than restore from a shared
path. Concurrent agents and in-place fixes do not mix.
