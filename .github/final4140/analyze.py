#!/usr/bin/env python3
"""Checks one upgrade run dir. Usage: analyze.py <dir> <mode> <label>
mode: success | failpull | faillate | noop. Env: GLOBAL_AUTH, RES, NEW_MD5, OLD_MD5, NEW_VERSION, OLD_VERSION, IMG_JSON, IMG_OLD_JSON, NEW_MIGS, PHPSITES, HTMLSITES.
Expectations are derived from the two phars (img-versions.json diff, migration list diff) and core's upgrade code, not from literals."""
import os, re, sys, json, datetime, collections

d, mode, label = sys.argv[1:4]
env = os.environ
res = open(env["RES"], "a")
glob = env.get("GLOBAL_AUTH", "0") == "1"
phpsites, htmlsites = env["PHPSITES"].split(), env["HTMLSITES"].split()
allsites = phpsites + htmlsites
new_v, old_v = env["NEW_VERSION"], env["OLD_VERSION"]
img = json.load(open(env["IMG_JSON"]))
img_old = json.load(open(env["IMG_OLD_JSON"]))
changed = {k for k, v in img.items() if img_old.get(k) != v}
new_migs = [l.split("/", 1) for l in open(env["NEW_MIGS"]).read().split()]
new_names = sorted(n for _, n in new_migs)
new_container = sorted(n for t, n in new_migs if t == "container")
new_db = sorted(n for t, n in new_migs if t == "db")
proxy_tag = img.get("easyengine/nginx-proxy", "")
proxy_changed = "easyengine/nginx-proxy" in changed


def rd(p, default=""):
    try:
        return open(os.path.join(d, p), errors="replace").read()
    except OSError:
        return default


def chk(name, ok, got):
    line = f"{'PASS' if ok else 'FAIL'} | {label}: {name} | {got}"
    print(line)
    res.write(line + "\n")


def info(text):
    line = f"INFO | {label}: {text}"
    print(line)
    res.write(line + "\n")


log = rd("ee.log.part")
start, end = map(float, rd("window.txt").split())
rc = rd("rc.txt").strip()


def logtime(pattern):
    """UTC epoch of the first ee.log line matching pattern (1 s resolution)."""
    m = re.search(r"^\[(\d\d-\d\d-\d{4} \d\d:\d\d:\d\d)\][^\n]*" + pattern, log, re.M)
    if not m:
        return None
    return datetime.datetime.strptime(m.group(1), "%d-%m-%Y %H:%M:%S").replace(tzinfo=datetime.timezone.utc).timestamp()


def hms(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%H:%M:%S.%f")[:12] if t else "n/a"


def day_ts(hmsstr):
    """Probe/poll timestamps are HH:MM:SS.mmm UTC on the day of the run."""
    base = datetime.datetime.fromtimestamp(start, datetime.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    h, m, s = hmsstr.split(":")
    t = base + int(h) * 3600 + int(m) * 60 + float(s)
    return t + 86400 if t < start - 3600 else t


def table(p):
    return set(l.split("|")[1] for l in rd(p).splitlines() if "|" in l)


def ctab(p):
    """name -> (image, id, status) from a containers.txt."""
    out = {}
    for l in rd(p).splitlines():
        c = l.split("\t")
        if len(c) >= 4:
            out[c[0]] = (c[1], c[2], c[3])
    return out


def counts(p):
    """file -> count from `grep -c` output (file:count)."""
    out = {}
    for l in rd(p).splitlines():
        f, _, n = l.rpartition(":")
        if f:
            out[f] = int(n or 0)
    return out


def md5s(p):
    return dict((l.split()[1], l.split()[0]) for l in rd(p).splitlines() if len(l.split()) == 2)


# Probe samples: {key: [(t, code, secs)]}
probe = collections.defaultdict(list)
for line in rd("probe.txt").splitlines():
    parts = line.split()
    if not parts:
        continue
    t = day_ts(parts[0])
    for kv in parts[1:]:
        k, _, v = kv.partition("=")
        c, _, s = v.partition("/")
        probe[k].append((t, c, float(s or 0)))

# Proxy starts from docker events.
proxy_starts = []
for line in rd("docker-events.txt").splitlines():
    p = line.split()
    if len(p) >= 5 and p[1] == "container" and p[2] == "start" and p[3] == "services_global-nginx-proxy_1":
        proxy_starts.append((int(p[0]) / 1e9, p[4]))
new_proxy = next((t for t, image in proxy_starts if image.endswith("nginx-proxy:" + proxy_tag)), None)

mig_before, mig_after = table("before/migrations.txt"), table("after/migrations.txt")
migrating = collections.Counter(re.findall(r"ee\.DEBUG: Migrating: (\S+)", log))
staged = log.count("Staged the wildcard auth files")
promoted = log.count("Promoted the staged wildcard auth files")
old_tpl = log.count("nginx-proxy template: old")
version = dict(l.split("|", 1) for l in rd("after/options.txt").splitlines() if "|" in l).get("version", "?")
ee_md5 = rd("after/ee.md5").split()[0] if rd("after/ee.md5") else "?"
cb, ca = ctab("before/containers.txt"), ctab("after/containers.txt")
update_ee = [n for n in ca if n.startswith("update-ee-")]


def site_of(name):
    for s in allsites:
        if name.startswith(s.replace(".", "") + "-"):
            return s
    return None


def never(key, code):
    s = probe.get(key, [])
    return sum(1 for x in s if x[1] == code), len(s)


def sibling_checks():
    if glob:
        n, tot = never("shopg", "401")
        chk("sibling shop with the global user never 401 (the ms auth never leaked)", n == 0 and tot > 0, f"{n}/{tot} samples 401")
        n, tot = never("shopu1", "200")
        chk("sibling shop never accepts the ms user u1", n == 0 and tot > 0, f"{n}/{tot} samples 200")
    else:
        n, tot = never("p:shop.f4-ms.test", "401")
        chk("sibling shop (no credentials) never 401", n == 0 and tot > 0, f"{n}/{tot} samples 401")
    info(f"forced container event cycles during the run: {rd('events-forced.txt').count('restart dummy')}")


def availability():
    out = []
    for k in sorted(probe):
        if not k.startswith("l:"):
            continue
        s = [x for x in probe[k] if start - 1 <= x[0] <= end + 5]
        bad = [x for x in s if not re.match(r"[23]", x[1])]
        longest, cur = 0.0, None
        for t, c, _ in s:
            if not re.match(r"[23]", c):
                cur = t if cur is None else cur
                longest = max(longest, t - cur + 0.5)
            else:
                cur = None
        out.append(f"{k[2:]} {len(bad)}/{len(s)} longest {longest:.1f}s")
    info("availability via 127.0.0.1 during the run (non-2xx/3xx / samples, longest outage): " + "; ".join(out))


def running_before(name):
    return name in cb and cb[name][2].startswith("Up")


def images_checks():
    info("images changed between the phars: " + (" ".join(f"{k} {img_old.get(k, 'none')}->{img[k]}" for k in sorted(changed)) or "none"))
    bad = []
    for name, (image, _, _) in ca.items():
        repo, _, tag = image.partition(":")
        if repo not in img or name.startswith("f4-event"):
            continue
        # GlobalContainers::get_updated_global_images() only migrates running global services; a stopped one keeps its tag.
        want = cb[name][0].partition(":")[2] if name.startswith("services_global-") and name in cb and not running_before(name) else img[repo]
        if tag != want:
            bad.append(f"{name}={image} (want {want})")
    chk("every EE container on its expected tag (img-versions.json; stopped global services keep theirs)", not bad, "mismatches: " + (", ".join(bad) or "none"))
    info("images in use: " + " ".join(sorted(set(v[0] for v in ca.values() if v[0].startswith("easyengine/")))))
    for repo in sorted(changed):
        tags = sorted(set(v[0].partition(":")[2] for n, v in ca.items() if v[0].partition(":")[0] == repo and (not n.startswith("services_global-") or running_before(n))))
        if tags:
            chk(f"changed image {repo}: its containers on {img[repo]}", tags == [img[repo]], ",".join(tags))
        else:
            info(f"changed image {repo}: no container in the population uses it")
    nr = "services_global-newrelic-daemon_1"
    info(f"newrelic-daemon: before {cb.get(nr, ('absent', '', ''))[0]} [{cb.get(nr, ('', '', 'n/a'))[2]}], after {ca.get(nr, ('absent', '', ''))[0]} [{ca.get(nr, ('', '', 'n/a'))[2]}]")
    opts = dict(l.split("|", 1) for l in rd("after/options.txt").splitlines() if "|" in l)
    # Containers::create_database_entry() updates the existing rows of every updated image; images without a row (skipped at install) get none.
    # 4.14.0: a global service that was stopped keeps its old image and its options row until it is enabled (plan L2-04/L2-15).
    stopped = {cb[n][0].partition(":")[0] for n in cb if n.startswith("services_global-") and not running_before(n)}
    obad = [f"{k}={v}" for k, v in opts.items() if k in img and v != (img_old.get(k, img[k]) if k in stopped else img[k])]
    chk("options table image tags = img-versions.json (stopped globals: old tag)", not obad, ", ".join(obad) or f"all as expected (stopped: {' '.join(sorted(stopped)) or 'none'})")


def recreate_checks():
    """Containers::migrate_site_containers() recreates an enabled site when `docker-compose images` lists an updated image; php* and newrelic-daemon are only exempt from the pre-pull."""
    def site_images(s):
        return {v[0].partition(":")[0] for n, v in cb.items() if site_of(n) == s}

    def recreated(names):
        return any(n not in ca or ca[n][1] != cb[n][1] for n in names)

    exp = sorted(s for s in allsites if site_images(s) & changed)
    got = sorted(s for s in allsites if recreated([n for n in cb if site_of(n) == s]))
    chk("recreated sites = sites with a container on a changed image", exp == got, f"expected [{' '.join(exp)}] got [{' '.join(got)}]")
    bad = []
    for n in sorted(x for x in cb if x.startswith("services_global-")):
        want = cb[n][0].partition(":")[0] in changed and running_before(n)
        if want != recreated([n]):
            bad.append(f"{n} expected {'recreate' if want else 'kept'}")
    chk("global containers recreated = the running ones on a changed image", not bad, ", ".join(bad) or "as expected")
    return exp


def reload_checks(exp_sites):
    bad = []
    for s in phpsites:
        want = 1 if s in exp_sites else 0
        f, sp = log.count(f"Executing reload-site-nginx-{s}..."), log.count(f"Executing reload-support-nginx-{s}...")
        if f != want or sp != want:
            bad.append(f"{s} fwd={f} support={sp} want {want}")
    chk("reload-support-nginx + reload-site-nginx once per recreated WP/PHP site, never for others", not bad, ", ".join(bad) or f"{sum(1 for s in phpsites if s in exp_sites)}/{len(phpsites)} sites reloaded")
    nr = rd("noroute-during.txt").split("\n")
    info("No route to host in error.log during the upgrade (MIG-26 residual, known): " + (" ".join(l.replace(" ", "=") for l in nr if l and not l.endswith(" 0")) or "none"))


def proxy_checks():
    if proxy_changed:
        chk(f"proxy recreated on nginx-proxy:{proxy_tag}", bool(new_proxy), [f"{hms(t)} {i}" for t, i in proxy_starts])
    else:
        n = "services_global-nginx-proxy_1"
        chk("nginx-proxy not recreated (tag unchanged)", not proxy_starts and n in ca and n in cb and ca[n][1] == cb[n][1], f"{len(proxy_starts)} starts; {ca.get(n, ('?',))[0]}")
    chk("proxy has the acl template", rd("after/template-acl-count.txt").strip() not in ("", "0"), rd("after/template-acl-count.txt").strip())


def auth_files_checks(strict):
    """htpasswd untouched; _acl files change only where seed.sh wrote an entry (the _acl cleanup migration), and those end clean."""
    chk("htpasswd files unchanged", rd("before/htpasswd.md5") == rd("after/htpasswd.md5"), "same" if rd("before/htpasswd.md5") == rd("after/htpasswd.md5") else "DIFF")
    seeded = {f for f, n in counts("before/acl-seeded.txt").items() if n > 0}
    mb, ma = md5s("before/acl.md5"), md5s("after/acl.md5")
    other = [f for f in set(mb) | set(ma) if f not in seeded and mb.get(f) != ma.get(f)]
    dirty = [f for f, n in counts("after/acl-seeded.txt").items() if n > 0 and f in seeded]
    fixed = [f for f in seeded if mb.get(f) != ma.get(f)]
    chk("_acl files: only the ones holding a seeded entry changed", not other, ", ".join(other) or f"{len(fixed)}/{len(seeded)} seeded files rewritten, others identical")
    if strict:
        chk("_acl files that held a seeded entry are clean now", not dirty and len(fixed) == len(seeded), ", ".join(dirty) or f"{len(seeded)} clean")
    st = lambda p: "\n".join(l for l in rd(p).splitlines() if l.split(" ")[0].replace("vhost.d/", "") not in seeded)
    chk("auth-stat.txt identical except the seeded _acl files", st("before/auth-stat.txt") == st("after/auth-stat.txt"), "same" if st("before/auth-stat.txt") == st("after/auth-stat.txt") else "DIFF")


def auth_window():
    if not proxy_changed:
        info("auth window: n/a (the proxy is not recreated in this upgrade)")
        return
    t_promote = logtime("Promoted the staged wildcard auth files")
    if new_proxy and t_promote:
        info(f"auth window: new proxy started {hms(new_proxy)}, promoted {hms(t_promote)} = {t_promote - new_proxy:.0f} s")
    for k in ["p:a.f4-ms.test", "p:x.y.f4-ms.test", "p:foo.f4-wild.test", "p:f4-alias.test", "p:f4-ms.test"]:
        s = [x for x in probe.get(k, []) if x[0] >= start]
        not401 = [x for x in s if x[1] != "401"]
        info(f"{k[2:]} (no credentials) not-401 samples: {len(not401)}/{len(s)}, last not-401 {hms(not401[-1][0]) if not401 else 'n/a'}")


def no_wildcard_staging():
    chk("no wildcard-auth stage/promote (that migration was applied by the old version)", old_tpl == 0 and staged == 0 and promoted == 0, f"template-old={old_tpl} staged={staged} promoted={promoted}")
    chk("staging dir absent", "No such file" in rd("after/staging.txt"), rd("after/staging.txt").strip()[:80])


chk("run exit code", {"success": rc == "0", "noop": rc == "0", "failpull": rc == "1", "faillate": rc == "1"}[mode], f"rc={rc}; {rd('cmd.txt').strip().splitlines()[-1] if rd('cmd.txt') else ''}")
info("timing: " + " ".join(rd("cmd.txt").split()))

if mode == "success":
    chk("ee version after", new_v == version and ee_md5 == env["NEW_MD5"], f"options.version={version} ee md5={ee_md5}")
    newrows = sorted(mig_after - mig_before)
    chk("new migration rows = the migrations new in the phar", newrows == new_names, ",".join(newrows) or "none")
    chk("every migration ran exactly once", (not new_names and not migrating) or (bool(migrating) and max(migrating.values()) == 1 and set(migrating) == set(newrows)), dict(migrating))
    no_wildcard_staging()
    proxy_checks()
    auth_files_checks(True)
    images_checks()
    reload_checks(recreate_checks())
    chk("no update-ee-* support containers left", not update_ee, ",".join(update_ee) or "none")
    sibling_checks()
    auth_window()
    availability()
elif mode == "failpull":
    chk("Docker Hub blocked during the run", rd("block-check.txt").strip() == "blocked", rd("block-check.txt").strip())
    out = rd("cliinfo.out") + rd("cliinfo.err") + rd("update.out")
    chk("pull failure reported + 'PHAR is broken'", "Unable to pull" in out + log and "PHAR is broken" in out, re.findall(r"Unable to pull[^\n]*", out + log)[:1])
    chk("installed phar is still the old one", ee_md5 == env["OLD_MD5"], ee_md5)
    chk(f"options.version stays {old_v}", version == old_v, version)
    # CustomContainerMigrations::revert_executed_migrations(): down() + row deleted for every container migration of this run; db migrations have no undo.
    rev = [n for n in new_container if f"Reverting: {n}" in log and f"Reverted: {n}" in log]
    chk("container migrations of this run reverted", rev == new_container, f"{len(rev)}/{len(new_container)} reverted")
    chk("migrations table: only the new db migrations added", mig_before <= mig_after and sorted(mig_after - mig_before) == new_db, f"{len(mig_before)} -> {len(mig_after)} rows")
    no_wildcard_staging()
    auth_files_checks(True)
    for f in ["options.txt", "compose.md5", "containers-ni.txt"]:
        chk(f"{f} identical to before", rd("before/" + f) == rd("after/" + f), "same" if rd("before/" + f) == rd("after/" + f) else "DIFF")
    chk("no update-ee-* support containers left", not update_ee, ",".join(update_ee) or "none")
    chk("no /tmp/ee_*.phar left", rd("tmp-phars.txt").strip() == "", rd("tmp-phars.txt").strip() or "none")
    chk("hosts file restored", "hosts restored byte-identical" in rd("cmd.txt"), "")
    chk("auth matrix identical to before", rd("matrix-before.txt") == rd("matrix-after.txt"), "same" if rd("matrix-before.txt") == rd("matrix-after.txt") else "DIFF")
    sibling_checks()
    availability()
elif mode == "faillate":
    out = rd("cliinfo.out") + rd("cliinfo.err") + log
    # int-all copy: upgrade r2 removes the old backup before copying (Symfony "Failed to remove file"); 4.13.x failed in the copy.
    chk("failure in ee-update-docker-compose (after the image migration)", re.search(r"Failed to (copy|remove)", out) is not None, re.findall(r"[^\n]*Failed to (?:copy|remove)[^\n]*", out)[:1])
    chk("installed phar is still the old one", ee_md5 == env["OLD_MD5"], ee_md5)
    chk(f"options.version stays {old_v}", version == old_v, version)
    # Runner::migrate(): ee-keep-container-migrations runs right after the image migration, so a later failure reverts none.
    chk("container migrations kept, none reverted", "Keeping the container migrations of this run" in log and "Reverting:" not in log, "kept" if "Keeping the container migrations of this run" in log else "no keep line")
    chk("new migration rows present", set(new_names) <= mig_after, ",".join(sorted(set(new_names) - mig_after)) or "all present")
    no_wildcard_staging()
    proxy_checks()
    auth_files_checks(True)
    images_checks()
    recreate_checks()
    chk("no update-ee-* support containers left", not update_ee, ",".join(update_ee) or "none")
    sibling_checks()
    availability()
elif mode == "noop":
    chk("ee version after", new_v == version and ee_md5 == env["NEW_MD5"], f"options.version={version} ee md5={ee_md5}")
    chk("no migration re-run", not migrating and mig_before == mig_after, dict(migrating) or "none")
    no_wildcard_staging()
    for f in ["htpasswd.md5", "acl.md5", "compose.md5"]:
        chk(f"{f} unchanged", rd("before/" + f) == rd("after/" + f), "same" if rd("before/" + f) == rd("after/" + f) else "DIFF")
    same = [l.split("\t")[:3] for l in rd("before/containers.txt").splitlines() if "f4-event" not in l] == [l.split("\t")[:3] for l in rd("after/containers.txt").splitlines() if "f4-event" not in l]
    chk("no container recreated (name, image, ID)", same, "same" if same else "DIFF")
    sibling_checks()
