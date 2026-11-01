# jsh - the full guide

`jsh` is a JSON toolkit for Windows **cmd / .bat** files. Read values out of JSON, list keys, search, filter arrays, edit files, and load a whole JSON file into batch variables.

It is two files that must stay together:

| File | What it is |
|------|------------|
| `jsh.bat` | thin wrapper you actually run from cmd |
| `jsh.ps1` | the engine (uses the PowerShell built into Windows) |

No installs needed. The wrapper runs PowerShell with `-ExecutionPolicy Bypass` for that one process only, so you don't have to change any system settings.

> **Tested on:** PowerShell 7. The Windows built-in PowerShell 5.1 and the `.bat` wrapper itself were not tested on a real Windows machine, so if something errors, note the exact message.

---

## 1. Install

1. Put `jsh.bat` and `jsh.ps1` in the same folder, e.g. `C:\tools\jsh\`.
2. Add that folder to your PATH (optional, but then you can type `jsh` from anywhere and inside other scripts).
3. Check it works:

```bat
jsh -tst
```

It should print `true`. If it does, cmd, the wrapper, and PowerShell are all working.

> Not on PATH? Run it as `C:\tools\jsh\jsh` or `.\jsh` from its folder.

---

## 2. Quick start

Say you have `servers.json`:

```json
{
  "project": "homelab",
  "servers": [
    { "name": "web1", "host": "192.168.1.10", "port": 22,   "user": "james", "tags": ["web", "prod"], "up": true  },
    { "name": "nas",  "host": "192.168.1.20", "port": 2222, "user": "admin", "tags": ["storage"],     "up": true  },
    { "name": "pi",   "host": "192.168.1.30", "port": 22,   "user": "pi",    "tags": [],              "up": false }
  ],
  "settings": { "timeout": 5, "retries": 3, "notes": "line one\nline two", "backup": { "dir": "D:\\backups", "keep": 7 } }
}
```

```bat
jsh get .project -f servers.json
jsh get .servers[1].host -f servers.json
jsh length .servers -f servers.json
jsh keys .settings -f servers.json
jsh where .servers up false name -f servers.json
```

Output:

```
homelab
192.168.1.20
3
timeout
retries
notes
backup
pi
```

---

## 3. Giving jsh the JSON

There are three ways. Pick one per command.

| Method | Example |
|--------|---------|
| File | `jsh get .name -f data.json` |
| Pipe (stdin) | `type data.json \| jsh get .name` |
| Inline string | `jsh get .a -s "{\"a\":1}"` |

Notes:

- **Prefer `-f` or a pipe.** Inline `-s` needs awkward quote-escaping in cmd.
- Files should be **UTF-8** (a BOM is fine). CRLF or LF line endings both work.
- If you give none of the three and aren't piping anything in, you get `jsh: no input`.
- Arrays and plain values work as the top level too, not just objects: `echo [1,2,3] | jsh length`.

---

## 4. Path syntax

A path says where in the JSON to look.

| You want | Write | Notes |
|----------|-------|-------|
| a key | `.name` or `name` | leading dot is optional |
| nested key | `.settings.backup.dir` | |
| array item | `.servers[0]` | zero-based |
| both | `.servers[1].tags[0]` | |
| odd key (spaces, dots, starts with a digit) | `.meta['my key']` | single quotes inside the brackets |
| the whole document | `.` or leave the path off | |

Keys made of letters, digits, `_` and `-` (not starting with a digit) are "plain" and can use dots. Anything else needs the bracket form.

**In cmd,** wrap a path in double quotes if it has spaces or special characters:

```bat
jsh get ".meta['my key']" -f data.json
```

The `["double quote"]` form also works but is painful to type in cmd, so use the single-quote form.

---

## 5. Options

Options can go anywhere after the command name.

| Option | Long form | What it does |
|--------|-----------|--------------|
| `-f FILE` | `--file` | read JSON from a file |
| `-s "JSON"` | `--string` | read JSON from the argument |
| `-d VALUE` | `--default` | (`get`) print this instead of failing when the path doesn't exist |
| `-c` | `--compact` | print JSON on one line instead of pretty-printed |
| `-j` | `--json` | (`get`) keep JSON quoting on a string, e.g. `"hi"` instead of `hi` |
| `-i` | `--in-place` | (`set`/`del`) write the result back into the `-f` file |
| `--str` | | (`set`) force the new value to be a string |
| `--prefix P` | | (`env`) variable-name prefix (default `JSON_`) |
| `-tst` | | print `true` and exit (self-test) |
| `-h` | `--help` | show usage |

`jsh` with no arguments, or `jsh help`, also prints the usage.

---

## 6. Commands

### `get PATH` - read a value

```bat
jsh get .project -f servers.json                 &:: homelab
jsh get .servers[1].port -f servers.json         &:: 2222
jsh get .settings.backup.dir -f servers.json     &:: D:\backups
```

What gets printed:

- **string** - the text itself, with escapes decoded (a `\n` in the JSON becomes a real line break)
- **number** - the number
- **true/false** - `true` / `false`
- **null** - `null`
- **object/array** - pretty JSON (2-space indent). Add `-c` for one line.

```bat
jsh get .settings.backup -c -f servers.json
```
```
{"dir":"D:\\backups","keep":7}
```

`-j` keeps a string JSON-quoted:

```bat
jsh get .settings.notes -j -f servers.json
```
```
"line one\nline two"
```

**Missing path:** prints `jsh: path not found: ...` to stderr and sets errorlevel 1. With `-d`, it prints your default and exits 0 instead:

```bat
jsh get .servers[0].timeout -d 30 -f servers.json    &:: 30
```

`-d` only kicks in when the path doesn't exist. A path that exists but holds `null` prints `null`.

### `keys [PATH]` - list keys or indexes

```bat
jsh keys .settings -f servers.json
```
```
timeout
retries
notes
backup
```

For an array it prints `0`, `1`, `2`... For anything else it fails with `not an object or array` (errorlevel 3).

### `values [PATH]` - list child values

One per line. Strings print as plain text; nested objects/arrays print compact.

```bat
jsh values .settings.backup -f servers.json
```
```
D:\backups
7
```

```bat
jsh values .servers[0].tags -f servers.json
```
```
web
prod
```

### `length [PATH]` - count things

- object or array: number of children
- string: number of characters
- anything else: error (errorlevel 3)

```bat
jsh length .servers -f servers.json     &:: 3
jsh length .project -f servers.json     &:: 7  (characters in "homelab")
```

### `type [PATH]` - what is it?

Prints one of `object`, `array`, `string`, `number`, `bool`, `null`.

```bat
jsh type .servers -f servers.json           &:: array
jsh type .settings.timeout -f servers.json  &:: number
jsh type .servers[0].up -f servers.json     &:: bool
```

### `has PATH` - does it exist?

Prints nothing. Check the errorlevel: `0` = exists, `1` = doesn't.

```bat
jsh has .settings.backup -f servers.json
if errorlevel 1 (echo no backup section) else (echo has backup section)

jsh has .servers[5] -f servers.json && echo yes || echo no
```

### `paths [PATH]` - every leaf as `path = value`

Great for seeing what paths exist. Strings are quoted. Empty `{}`/`[]` are shown as-is.

```bat
jsh paths .settings -f servers.json
```
```
.settings.timeout = 5
.settings.retries = 3
.settings.notes = "line one\nline two"
.settings.backup.dir = "D:\\backups"
.settings.backup.keep = 7
```

Run `jsh paths -f file.json` with no path to see the whole file this way.

### `find KEY` - where does this key appear?

Finds every object key with exactly this name (case-sensitive), anywhere in the document.

```bat
jsh find user -f servers.json
```
```
.servers[0].user = "james"
.servers[1].user = "admin"
.servers[2].user = "pi"
```

### `search TEXT` - where does this value appear?

Finds every leaf value containing the text (case-insensitive). It searches values, not key names.

```bat
jsh search backup -f servers.json
```
```
.settings.backup.dir = "D:\\backups"
```

### `where ARRAY FIELD VALUE [OUT]` - filter a list

Looks at each item of `ARRAY`, keeps those whose `FIELD` equals `VALUE` exactly (case-sensitive, compared as text), and prints either the whole item (compact) or just the `OUT` field.

```bat
jsh where .servers up false name -f servers.json     &:: pi
jsh where .servers port 22 host -f servers.json      &:: 192.168.1.10  and  192.168.1.30
jsh where .servers user admin -f servers.json        &:: whole item for nas, on one line
```

- `FIELD` and `OUT` use the same path syntax as everywhere else (relative to each item).
- Booleans compare as `true` / `false`, null as `null`.
- Items that don't have the field are skipped.

### `pretty`, `minify`, `valid`

```bat
jsh pretty -f messy.json            &:: reformat nicely (2-space indent)
jsh minify -f pretty.json           &:: one line
jsh valid -f file.json              &:: no output; errorlevel 0 = valid, 2 = parse error
```

### `env [PATH] [--prefix P]` - JSON into batch variables

Prints `NAME=value` lines you can feed to `set`. This is the fast way to use JSON in a batch script (see section 8).

```bat
jsh env .settings.backup -f servers.json
```
```
JSON_settings_backup__len=2
JSON_settings_backup_dir=D:\backups
JSON_settings_backup_keep=7
```

Naming rules:

- Start with the prefix (default `JSON_`), then the path with every run of non-alphanumeric characters turned into a single `_`. `.servers[0].host` becomes `JSON_servers_0_host`.
- Every object/array also gets a `NAME__len=N` line with its child count (two underscores). The root's is `JSON__len`.
- Booleans become `true`/`false`, null becomes `null`, line breaks in values become spaces.

Gotchas:

- Values containing `!` or `%` can get mangled when loaded in a script with delayed expansion.
- An **empty string** value produces `NAME=`, which makes `set "NAME="` *delete* the variable. Test with `if defined`.
- Variable names are case-insensitive in cmd, so keys differing only by case would collide.

### `set PATH VALUE` - change or add a value

Prints the whole updated document. The file is **not** changed unless you add `-i -f FILE`.

```bat
jsh set .settings.retries 5 -f servers.json            &:: show result
jsh set .settings.retries 5 -i -f servers.json         &:: write it back
```

How the value is interpreted:

| You type | Stored as |
|----------|-----------|
| `5`, `-3`, `2.5`, `1e3` | number |
| `true`, `false` | boolean |
| `null` | null |
| `007` | string (leading zeros) |
| anything else | string |

Use `--str` to force a string: `jsh set .version 2 --str -i -f app.json` stores `"2"`.

What it can do:

- replace an existing value
- add a new key to an **existing** object: `jsh set .settings.region west -i -f servers.json`
- append to an array by using the next index: with 3 servers, `.servers[3]` appends

What it can't do:

- create missing parents (`.a.b.c` fails if `.a.b` doesn't exist)
- set an object or array as the new value (scalars only)
- skip over array indexes

On failure you get `path not found` (errorlevel 1).

### `del PATH` - remove a key or item

```bat
jsh del .servers[2] -i -f servers.json         &:: removes pi, later items shift down
jsh del .settings.notes -i -f servers.json
```

Deleting the root isn't allowed (errorlevel 3).

### About `-i` (editing files in place)

- The file is rewritten pretty-printed with 2-space indent (add `-c` for one line). It's saved as UTF-8 without BOM, with CRLF line endings.
- Key order is kept, but your original whitespace and formatting are not.
- **Make a backup first** if the file matters: `copy servers.json servers.json.bak`
- `-i` requires `-f`. It doesn't work with `-s` or piped input.

---

## 7. Exit codes (errorlevel)

| Code | Meaning |
|------|---------|
| `0` | success |
| `1` | path not found (and for `has`: "no") |
| `2` | usage error, unknown command, unreadable file, or invalid JSON |
| `3` | wrong type for the command (e.g. `keys` on a string) or deleting the root |

Error messages go to stderr (`jsh: ...`) so they won't pollute values you capture with `for /f`.

---

## 8. Using jsh inside .bat scripts

> In a `.bat` file, loop variables use two percent signs (`%%L`). At the command prompt they use one (`%L`).

### Grab one value

```bat
for /f "delims=" %%H in ('jsh get .servers[0].host -f servers.json') do set "host=%%H"
echo %host%
```

### Grab a value with a fallback

Set the fallback first. If `jsh` prints nothing (e.g. an error), the loop body never runs and your default stays:

```bat
set "port=22"
for /f "delims=" %%P in ('jsh get .servers[0].port -f servers.json') do set "port=%%P"
```

Or just use `-d`:

```bat
for /f "delims=" %%P in ('jsh get .servers[0].port -d 22 -f servers.json') do set "port=%%P"
```

### Loop over a list of values

```bat
for /f "delims=" %%N in ('jsh where .servers up true name -f servers.json') do echo online: %%N
```

### Branch on existence or validity

```bat
jsh valid -f config.json
if errorlevel 1 (
  echo config.json is not valid JSON
  exit /b 1
)

jsh has .settings.backup -f config.json
if errorlevel 1 echo no backup section
```

### Load everything at once with `env` (fastest)

PowerShell takes roughly a third of a second to start. Calling `jsh` ten times in a loop is slow, so call `env` **once** and read variables:

```bat
@echo off
setlocal enabledelayedexpansion

for /f "delims=" %%L in ('jsh env -f servers.json') do set "%%L"

set /a last=%JSON_servers__len%-1
for /l %%i in (0,1,%last%) do (
  echo !JSON_servers_%%i_name! - !JSON_servers_%%i_host!:!JSON_servers_%%i_port!
)
```

Why `!var!` instead of `%var%` inside the loop: the loop body is parsed once, so `%...%` would expand before `%%i` has a value. `!...!` (delayed expansion) expands each time around.

If `jsh` isn't on your PATH, replace `jsh` inside the `for /f` with the full path in quotes: `"C:\tools\jsh\jsh.bat"`.

### Example: a tiny server status script

*(Example only, not tested against real servers. Needs the Windows OpenSSH client, which is built into Windows 10/11 as an optional feature, and SSH keys already set up.)*

```bat
@echo off
setlocal enabledelayedexpansion
for /f "delims=" %%L in ('jsh env -f "%~dp0servers.json"') do set "%%L"

set /a last=%JSON_servers__len%-1
for /l %%i in (0,1,%last%) do (
  set "name=!JSON_servers_%%i_name!"
  set "host=!JSON_servers_%%i_host!"
  set "port=!JSON_servers_%%i_port!"
  set "user=!JSON_servers_%%i_user!"
  echo === !name! ^(!user!@!host!:!port!^) ===
  ssh -o ConnectTimeout=5 -o BatchMode=yes -p !port! !user!@!host! "uptime"
)
```

---

## 9. Quoting and special characters in cmd

| Situation | What to do |
|-----------|-----------|
| path or value has spaces | wrap it in double quotes |
| path has `& \| < > ^` | wrap it in double quotes |
| key has spaces or dots | `".meta['my key']"` |
| need a literal `%` in a `.bat` | write `%%` |
| JSON on the command line (`-s`) | escape inner quotes as `\"`, or better, use `-f` / a pipe |
| piping JSON | `type file.json \| jsh ...` or `echo {"a":1} \| jsh get .a` |

Backslashes in Windows paths are fine as values (`jsh set .dir D:\backups -i -f cfg.json`), but remember JSON files store them doubled (`"D:\\backups"`). `jsh` handles that for you when reading and writing.

---

## 10. Notes on output

- **Numbers** are printed in a normal form, so `1.5e3` in the file comes out as `1500`.
- **Strings** printed by `get`/`values`/`keys` have their escapes decoded. Use `-j` (get), `paths`, `find`, or `search` to see JSON-style escaped strings.
- **Non-English characters:** the console must use a UTF-8 code page to show them correctly. Run `chcp 65001` first if you see garbled text. Save your JSON files as UTF-8.
- **Key order** is preserved.
- **`-tst`** works anywhere in the arguments, so you can't use the literal text `-tst` as a value.

---

## 11. Troubleshooting

| Problem | Likely cause / fix |
|---------|--------------------|
| `'jsh' is not recognized` | folder isn't on PATH. Use the full path or `cd` to the folder |
| `jsh -tst` prints nothing / errors | `jsh.ps1` isn't next to `jsh.bat`, or PowerShell is blocked by company policy |
| "running scripts is disabled" | the wrapper already bypasses policy for its own process. If it still appears, an admin-enforced policy is blocking it |
| `jsh: no input` | you forgot `-f file.json` (or a pipe) |
| `jsh: cannot read file` | wrong path/name. Quote paths with spaces |
| `jsh: parse error` | invalid JSON. Run `jsh valid -f file.json`. Common causes: trailing commas, comments, single-quoted strings |
| `jsh: path not found` | check the exact path with `jsh paths -f file.json` |
| key with a dot or space isn't found | use bracket form: `".obj['my key']"` |
| garbled accents | `chcp 65001`, and save the JSON as UTF-8 |
| slow when called in a loop | use `env` once instead |
| variable missing after `env` | its value was an empty string (`set "X="` deletes), so use `if defined` |

---

## 12. Limitations

- Each call starts PowerShell (about 0.3s). Use `env` for bulk reads.
- `set` writes scalars only and can't create missing parent paths.
- Duplicate keys in one object aren't supported.
- Very large JSON files will be slow.
- Comments and trailing commas in JSON aren't officially supported.
- Not tested on Windows' built-in PowerShell 5.1 or on a real Windows machine. Only on PowerShell 7.

---

## 13. Cheat sheet

```text
jsh -tst                              prints true
jsh get PATH [-d DEFAULT] [-c] [-j]   read a value
jsh keys [PATH]                       keys / indexes
jsh values [PATH]                     child values
jsh length [PATH]                     count / string length
jsh type [PATH]                       object|array|string|number|bool|null
jsh has PATH                          errorlevel only
jsh paths [PATH]                      every leaf as path = value
jsh find KEY                          where a key name appears
jsh search TEXT                       where a value contains TEXT
jsh where ARRAY FIELD VALUE [OUT]     filter a list
jsh env [PATH] [--prefix P]           NAME=value lines for set
jsh set PATH VALUE [--str] [-i]       change/add a scalar
jsh del PATH [-i]                     remove a key/item
jsh pretty | minify | valid           reformat / check

input:   -f FILE    |    -s "JSON"    |    pipe via stdin
paths:   .a.b   a.b   .list[0]   .obj['odd key']   (. = root)
errors:  0 ok, 1 not found, 2 usage/parse, 3 wrong type
```
