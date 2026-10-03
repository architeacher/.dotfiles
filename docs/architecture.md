# Architecture

How secrets and key backups work.

## Secrets in `private/`

Secrets are tracked only sops-encrypted. Every top-level dir ending in `.dist`
holds the encrypted files; the same path without `.dist` holds the decrypted
copies, which are git-ignored. Tools never read the encrypted files: their
configs point at the decrypted copies.

```mermaid
flowchart LR
    subgraph repo["private/ (git submodule)"]
        dist["X.dist/…<br/>encrypted, committed"]
        plain["X/…<br/>decrypted, git-ignored, mode 600"]
    end

    plain -- "make encrypt<br/>sops encrypt" --> dist
    dist -- "make decrypt<br/>sops decrypt" --> plain

    plain --> tools["tool configs<br/>(stow symlinks, includes)"]

    hook{{"pre-commit guard<br/>(make hooks, once per clone)"}}
    dist -. "git commit" .-> hook
    hook -- "only encrypted *.dist/** allowed" --> git[(private repo)]
```

| Piece | Role |
|---|---|
| `.sops.yaml` | creation rules and key groups for the encrypted files |
| `scripts/secrets.sh` | `encrypt` / `decrypt` / `hooks`; skips unchanged files, keeps newer local edits |
| `private/.gitignore` | allowlist: only `*.dist/**`, `.gitignore`, `.githooks/` |
| `private/.githooks/pre-commit` | refuses staged files outside `*.dist/` and plaintext inside it |

Unchanged detection uses mtimes: after every encrypt or decrypt, the decrypted
copy gets the encrypted file's mtime, so "edited" means "newer than its `.dist`".
That avoids decrypting (YubiKey touch + ssh key) just to compare.

## Key backups

The keys sops needs, each backed up passphrase-protected into
`BACKUP_ROOT/YYYYMMDD/`, optionally packed into one archive.

```mermaid
flowchart TB
    subgraph keys["Keys on the machine"]
        gpg["gpg secret key"]
        age["age identity"]
        yk["YubiKey identity stub"]
        sshk["sops ssh key"]
    end

    subgraph dir["BACKUP_ROOT/YYYYMMDD/"]
        gpgb["gpg backup"]
        ageb["age backup + .pub"]
        ykb["YubiKey stub backup + .pub"]
        sshb["ssh key backup + .pub"]
    end

    gpg -- gpg-backup --> gpgb
    age -- age-backup --> ageb
    yk -- age-yubikey-backup --> ykb
    sshk -- ssh-backup --> sshb

    dir -- pack --> archive["encrypted archive"]
    archive -- unpack --> dir

    dir -- "test-restore<br/>(temp dir, nothing touched)" --> check["checks pass"]
    dir -- "restore" --> keys
    dir -- "docker-extract<br/>(clean bash: container + verify)" --> check
```

Every check compares the restored key with the `.pub` / fingerprints saved in
the same backup. Passing `PUB=` / `FPR=` adds the independent check against a
value you noted elsewhere; `ssh-restore` also checks `.sops.yaml`.

### ssh-restore decisions

`ssh-restore` answers two questions: is the backup the right key, and how to put
it in `~/.ssh` without destroying anything. `ssh-test-restore` runs the same flow
into a temp dir instead of `~/.ssh`.

#### Terminology

The chart uses the default names. They follow `SSH_KEY`, and `DEST=` picks
another target.

| Term | Meaning |
|---|---|
| `id_ed25519_sops.age` | the backup: the private key, encrypted with your passphrase |
| `id_ed25519_sops.pub` | stored next to the `.age` file at backup time: its public key |
| `PUB` | optional `make` variable: the public key you noted elsewhere, e.g. `PUB="ssh-ed25519 AAAA…"` |
| `FORCE=1` | restore even if `.sops.yaml` does not list the key |
| `STAMP` | restore time, `YYYYMMDD-HHMMSS` |

#### Flow

`PUB` comes from outside the backup, so it also catches a swapped backup; the
backup `.pub` only catches a mismatch inside the backup. Hence `PUB` wins when passed.

The public key is computed from the temp private key (`ssh-keygen -y`), in
memory only.

Every abort happens before anything in `~/.ssh` is touched. Renamed files are kept,
never deleted. The key and its `.pub` are checked one by one: an identical key
(byte compare, so no passphrase prompt) is left as it is.

```mermaid
flowchart TD
    start([make ssh-restore]) --> dec["decrypt id_ed25519_sops.age<br/>into a temp private key file"]
    dec --> given{"PUB=… passed?"}
    given -- yes --> vspub{"public key computed from<br/>the temp private key = PUB?"}
    given -- no --> haspub{"backup has<br/>id_ed25519_sops.pub?"}
    haspub -- no --> refuse0[["abort: nothing to compare with"]]
    haspub -- yes --> vsfile{"public key computed from<br/>the temp private key<br/>= backup id_ed25519_sops.pub?"}
    vspub -- no --> refusepub[["abort: MISMATCH"]]
    vspub -- yes --> hassops{".sops.yaml exists?"}
    vsfile -- yes --> hassops
    vsfile -- no --> refusefile[["abort: MISMATCH"]]
    hassops -- "no (check skipped)" --> old
    hassops -- yes --> sops{"that public key listed<br/>in .sops.yaml?"}
    sops -- yes --> old
    sops -- no --> force{"FORCE=1?"}
    force -- no --> refuse2[["abort: stale backup?"]]
    force -- "yes (restore anyway)" --> old{"~/.ssh/id_ed25519_sops or its .pub<br/>holds another key?"}
    old -- yes --> aside["rename it to<br/>id_ed25519_sops.replaced-STAMP(.pub)"]
    old -- no --> write
    aside --> write["move the temp private key to<br/>~/.ssh/id_ed25519_sops, mode 600;<br/>write its .pub if missing"]
```

### Code layout

`scripts/backup.sh` is the only entry point: settings, `parse_args`, `prepare`,
and dispatch of `<command>` to a `cmd_*` function. The work lives in modules:

| Module | Commands |
|---|---|
| `scripts/backup/common.sh` | helpers: argument checks, backup paths, `latest`, temp dir |
| `scripts/backup/gpg.sh` | `gpg-fingerprint`, `gpg-backup`, `gpg-test-restore`, `gpg-restore` |
| `scripts/backup/age.sh` | `age-backup`, `age-test-restore`, `age-restore` |
| `scripts/backup/yubikey.sh` | `age-yubikey-backup`, `age-yubikey-test-restore` |
| `scripts/backup/ssh.sh` | `ssh-backup`, `ssh-test-restore`, `ssh-restore` |
| `scripts/backup/verify.sh` | `verify` |
| `scripts/backup/pack.sh` | `pack`, `unpack`, `run`, `summary` |

`run` starts each command as a new process of `backup.sh` (`BACKUP_SCRIPT`), so
one failing command stops the run and every command gets a clean temp dir.
