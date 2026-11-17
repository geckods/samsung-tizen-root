# samsung-tizen-root

**License: MIT.**

A minimal, evidence-backed description of a root path on a Samsung S95C
(`QN65S95CAFXZA`, Tizen 8, firmware `T-PTMCAKUC-0080`).

This repository covers **only the root path**. It does not describe, claim, or
include any other finding.

## Method

An AI coding agent (Hermes Agent, primarily running DeepSeek V4.1 Flash and some other models) read
Ghidra/decompiler output for the publicly downloadable firmware,
including `/usr/lib/libsdbd_plugin.so`, and helped identify the conversion and
the `vddebugmenu` menu behaviour described below.

The agent executed commands on the TV during the research. The evidence here is
the recorded device output, not a model assertion.

## Timeline

- **2026-09-12 21:01 UTC** — root first achieved on the S95C: arbitrary uid-0
  command execution through the root-marked SDB conversion
  `0 hyperuart_vddebugmenu`, driving `vddebugmenu`'s `BypassListMenu`.
- **2026-09-18** — first disclosed to Samsung and acknowledged by Samsung.

## The bug

The defect is a chain of trust and input-validation failures, not a memory
corruption bug. Three components combine:

- a root-marked SDB conversion that is still reachable;
- a debug menu that runs with elevated privilege and reads commands from its
  standard input; and
- a menu handler that passes that input to `system()` without quoting it.

The result is arbitrary command execution as uid 0. It requires developer mode
and a registered debug host; it is not a remote unauthenticated exploit, and it
does not install an application or use a signing certificate.

### Preconditions

- Developer mode enabled on the television.
- The attacking host is the host IP registered in developer mode.
- SDB connectivity to the television.
- The target build exposes the `hyperuart_vddebugmenu` conversion and the
  `BypassListMenu` path.

No application installation or developer certificate is required.

### How the chain works

1. **Root-marked SDB conversion.** `libsdbd_plugin.so` exposes the conversion
   `0 hyperuart_vddebugmenu`. The TV's normal `sdbd_rootperm` and
   `rootonoff_support` flags are disabled, but this conversion starts a helper
   that runs with elevated privilege.

2. **Privileged debug menu.** `hyperuart_vddebugmenu` starts `/usr/bin/vddebugmenu`
   as a privileged service. The service unit carries
   `SmackProcessLabel=System::Privileged`, `StandardInput=tty-force`,
   `TTYPath=/dev/console`, and `Restart=always`; that privileged context is what
   the root path relies on.

3. **Unquoted `system()` in the bypass menu.** The hidden `BypassListMenu`
   handles menu input as a task name and passes it to `system()` without quoting
   or validating it. A task string that begins `x;` therefore escapes the
   intended command and executes as uid 0.

4. **Input sequence.** The working sequence enters the menu, kills the
   `dlogd_sdb` log relay, submits a command of the form
   `x;<command>;#`, and exits. The exact input sequence is in `tvroot.sh`.

5. **UEP avoidance.** On this platform, `sh <file>` is refused for an unsigned
   script because the interpreter opens the file. Feeding the interpreter a
   string with `bash -c "$(cat <file>)"` avoids that file-open check. The
   minimal reproducer passes the command directly instead of a script file.

The `x;` prefix is the escape: the menu expects a task name, but the handler
passes the whole string to the shell. `pkill -f dlogd_sdb` stops the debug log
relay that would otherwise keep the SDB session busy; the following `x;...;#`
is the command that runs as root. The trailing `99` inputs exit the menu.

### Limits

- Live-tested on **`T-PTMCAKUC-0080`** only.
- The same primitives were observed statically in later builds; this is not a
  claim of live exploitability on Tizen 10.
- The root is **transient**. It is a command executed as uid 0, not a persistent
  service. A reboot ends the session; a software update can replace the
  privileged helper.
- The path requires developer mode and a registered debug host. It is not a
  remote unauthenticated exploit.
- No claim is made that this works on other Samsung models or builds without
  testing.

## Compatibility and evidence

Use the evidence label, not the model name, to decide what is known.

| Evidence | Target | Firmware / platform | Result |
|---|---|---|---|
| **Live** | `QN65S95CAFXZA` | `T-PTMCAKUC-0080`, Tizen 8.0.0 | `id` returned `uid=0(root)`; root path executed on 2026-09-12 |
| **Static only** | Later S95C/Tizen builds examined during the research | `vddebugmenu` / `libsdbd_plugin` primitives observed in the extracted platform | No live root result; do not treat this as compatible |
| **Static only** | Tizen 10 `T-PTMHDEUC-0100` | `vddebugmenu.service` and `libsdbd_plugin` inspected offline | No live Tizen 10 result; the Tizen 10 gate is unmeasured |
| **Not tested** | Any other Samsung model or region | — | No claim; do not extrapolate from the S95C |

“Live” means a command ran on the unit and returned uid 0. “Static only” means
the relevant files or strings were present in a firmware image; it is not a
successful root test.

## Before you run

- `sdb devices` shows the intended target.
- The TV is in Developer Mode, with the host computer registered as the Host PC IP.
- The TV and host are on the same trusted network. Do not expose SDB to the
  internet.
- `sdb connect <tv-ip>:26101` succeeds.

The script does not check the model or firmware. It is a minimal reproducer, not
a supported installer; whether the path works on a given Samsung TV is for the
user to determine.

## Reproducing it

1. **Enable developer mode on the TV.** Open the Apps screen, press `12345` on
   the remote, open the developer-mode dialog, enable it, enter the IP address
   of the computer that will run `sdb`, and reboot the TV. The exact menu label
   varies by firmware. Use the address the TV sees for that computer, not the
   TV's loopback address.

2. **Connect `sdb` to the TV.** With `sdb` in `PATH`, put the computer and TV on
   the same network, then run:

   ```sh
   sdb connect <tv-ip>:26101
   sdb devices
   ```

   The TV should appear in `sdb devices`. If it does not, recheck developer
   mode, the registered host IP, and reboot the TV after changing either.

3. **Run the reproducer.** From this repository:

   ```sh
   chmod +x tvroot.sh
   ./tvroot.sh <tv-ip>:26101 'id; echo shadow-byte=$(head -c1 /etc/shadow | wc -c)'
   ```

   The first argument is the SDB target; the second is the command to run as
   root. Keep the command simple and single-quoted.

4. **Verify the result.** The output should contain:

   ```text
   uid=0(root) gid=0(root) ... context="User::Shell"
   shadow-byte=1
   ```

   The `id` line proves uid 0. `shadow-byte=1` is a root-only read of the
   first byte of `/etc/shadow`. If the `id` line appears but the shadow read
   fails, stop and report the exact output; uid 0 does not necessarily mean
   every boundary is gone.

5. **Exit.** The sentinel closes the SDB session. The script does not install a
   service or write persistent state; the root command ends with the session.

## Prerequisites

- A Samsung Tizen TV with SDB and Developer Mode available. The script does not
  gate on model or firmware; the compatibility table records what was tested.
- Developer Mode enabled, with the host computer registered as the Host PC IP.
- Samsung `sdb`; **4.2.36** was used for the live test. Put it in `PATH` or set
  `SDB=/path/to/sdb`.
- A Linux host with `bash`, `awk`, `sed`, `grep`, `tr`, `timeout`, `mktemp`, and
  `seq`. The script is a host-side shell runner; it does not run on the TV.
- No Tizen Studio certificate, app package, or application install is needed.

## Troubleshooting

- **`sdb devices` is empty:** confirm Developer Mode and the Host PC IP, reboot
  the TV after changing them, then try `sdb kill-server`, `sdb start-server`,
  and `sdb connect <tv-ip>:26101` again.
- **`sdb: command not found`:** add Samsung's tools directory to `PATH`, or set
  `SDB` to the absolute `sdb` path.
- **No model check is performed:** the script will attempt the path on any SDB
  target. A different Samsung model may connect and still fail; treat that as an
  untested build, not as a vulnerability.
- **SDB connects but the script returns no root line:** do not loop. Capture the
  full output and stop; the build may not expose the same chain.
- **A plain `sdb shell` is empty or closed:** that is not the root test. The
  root path uses the `0 hyperuart_vddebugmenu` conversion, not a normal shell.

## Cleanup, reboot, and updates

- The script's only deliberate TV-side action besides the root command is
  `pkill -f dlogd_sdb`, which stops the debug log relay. A reboot restores it.
- The script stages no files and installs no service or listener.
- Root is transient. A reboot ends it; a firmware update can remove the
  privileged helper or close the path.
- If the command you run writes anything, that is your command's effect, not
  the script's. Use read-only commands when verifying.
- No uninstall step is required for the script itself.

## Boundary caveats

- The returned process context is **`User::Shell`**. uid 0 is real, but it is
  not a claim that Samsung's SMACK policy has been fully bypassed.
- UEP is not addressed by this path. Launching unsigned native binaries may
  still be refused.
- The script opens no network listener and installs no remote-access service.
- Developer Mode and the registered host IP are required. This is not an
  unauthenticated network exploit.

## Priority and prior art

**I may not be the first to find this.** Samsung's triage assessed the root
finding as not eligible because it had already been reported before this
submission. Public Tizen root work also exists through other mechanisms,
including [the Bishop Fox SDB install-command injection](https://bishopfox.com/blog/samsung-tizen-os-version-through-9-0),
the CALIF KantS2 physmap chain, and the archive-root bootstrap used by
[chris-ritsen's samsung-tv-root](https://github.com/chris-ritsen/samsung-tv-root)
and [invaliddayta's samsung-tv-tools](https://github.com/invaliddayta/samsung-tv-tools).

I found no public repository publishing the exact `vddebugmenu` /
`BypassListMenu` chain at the time of writing. That is a search result, not
proof of priority. I make no priority or "first" claim. The contribution here is
the documented mechanism and the live evidence, not the assertion that nobody
found it earlier.

Other public projects worth reading for their compatibility and evidence
practice: [Vetro](https://github.com/andrearicci93/vetro),
[commit-regrets](https://github.com/commit-regrets/samsung_tizen_tv_root),
[cfloinc](https://github.com/cfloinc/samsung-q70t-tizen-root),
[Amesa0036](https://github.com/Amesa0036/samsung-q95t-tizen-root),
[NHallam05](https://github.com/NHallam05/samsung-frame-root),
[Luminger](https://github.com/Luminger/samsung-tv-usb-root), and
[DemonKingSwarn](https://github.com/DemonKingSwarn/samsung-tv-tizen-root).

## Responsible use

Use only on devices you own or are explicitly authorized to test. This is
security research, not a universal rooting tool.

This is security research, not legal advice. Review your own disclosure and
publication obligations before redistributing it.

### Warranty and brick risk

Rooting may void your device's warranty and/or brick the device. Proceed only if
you accept that risk. No warranty is provided.

## Version

Version `0.1.0`. Changes are tracked in git; no release artifacts are published.

## License

MIT. See [LICENSE](LICENSE).

---
Written by geckods' Hermes Agent on behalf of geckods.
