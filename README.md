# Certadel Agent for Windows Server

Automated ACME certificate issuance, IIS installation, live verification and rollback
for Windows Server — packaged as a self-contained `.msi` that installs a Windows
Service with a web console on `https://<host>:9443`.

The agent's source (engine, plugins, console) lives in
[certadel-agent-core](https://github.com/Quantex-Secure/certadel-agent-core), included
here as the `core/` submodule. This repository holds the Windows installer.

## Install

Download `certadel-agent-windows-<version>.msi` from
[Releases](https://github.com/Quantex-Secure/certadel-agent-windows/releases), then from
an elevated prompt:

```powershell
msiexec /i certadel-agent-windows-<version>.msi /qn /l*v install.log
```

Browse to `https://<host>:9443` and sign in with a local or domain account that is a
member of the server's **Administrators** group. You'll get a browser warning until you
replace the bootstrap certificate (see below).

- **Upgrade:** install a newer MSI the same way; it replaces the old one in place.
- **Uninstall:** `msiexec /x certadel-agent-windows-<version>.msi /qn` — leaves
  `C:\ProgramData\AcmeManager` (database, secrets, logs) intact; delete it to fully reset.

> The MSI is not Authenticode-signed yet, so SmartScreen may warn on download.

## What the installer does

- Installs to `C:\Program Files\acme-manager` (no .NET runtime needed on the server).
- Registers and starts the **AcmeManager** Windows Service (display name *Certadel
  Agent*), auto-start, running as `LocalSystem`, restarting on failure.
- Adds an inbound firewall rule for **TCP 9443**.

On first start the service creates `C:\ProgramData\AcmeManager` and serves the console
with a self-signed certificate for the host.

## Authentication & access

- Sign-in is checked by Windows (`LogonUser`), so domain credentials work on a
  domain-joined server. Only members of an **authorized group** may sign in — by
  default `BUILTIN\Administrators` (which includes Domain Admins). To delegate without
  granting local admin, set it in `appsettings.json`:

  ```json
  "Auth": { "AllowedGroup": "CONTOSO\\Certificate Admins" }
  ```

- After 5 failed sign-ins for one account within 15 minutes the account is refused for
  5 minutes (doubling up to 1 hour), on top of a per-IP rate limit.
- Every mutating management-API call is logged with the principal, scheme, client
  address, route and result.
- `installer.script` and `validation.dns-01.script` run operator-supplied commands as
  the service account. Disable them with `"Plugins": { "AllowScriptPlugins": false }`.

## Service account & privileges

The service runs as **`LocalSystem`** by design: it writes the `LocalMachine\My`
certificate store (so IIS, Schannel, Exchange and RDS can use issued certificates) and
edits IIS bindings, both of which need local admin rights. Secrets are protected at rest
with DPAPI under the service account, so create them through the console, not from an
interactive session.

## Verified renewals and rollback

A renewal only counts as successful once the agent has seen the new certificate being
served: it connects to each IIS binding on loopback with the binding's host as SNI and
compares the thumbprint. If any endpoint still serves the old certificate, IIS is
re-bound to the previous certificate and the run fails with the reason. Use an
installer's `VerifyEndpoints` option for TLS terminated elsewhere, or `SkipVerification`
for endpoints the agent cannot reach (recorded as *unverified*).

## Replacing the bootstrap console certificate

1. Create a renewal whose source covers this server's own FQDN.
2. Add the installation **"acme-manager HTTPS endpoint"** (`installer.acme-manager-endpoint`).
3. Run it. The certificate is hot-swapped onto `:9443` without a restart and re-applied
   on every renewal. Delete `C:\ProgramData\AcmeManager\https-9443-acme.pfx` to revert.

A public CA can only issue for a publicly resolvable name; internal-only AD names need
an internal ACME CA.

## Moving from win-acme

**Import → win-acme** reads your existing win-acme renewals (including IIS targets and
DNS settings), lets you pick which to bring over, and after Certadel has issued a
replacement offers to cancel the matching win-acme renewal (via `wacs.exe`) so the two never fight.

## Build from source

Requires PowerShell 7 and the .NET 10 SDK; the WiX 6 toolset restores automatically.

```powershell
git clone --recurse-submodules https://github.com/Quantex-Secure/certadel-agent-windows
cd certadel-agent-windows
pwsh packaging/build-msi.ps1             # version defaults to core's VersionPrefix
```

Output: `packaging/AcmeManager.Installer/bin/x64/Release/acme-manager-setup.msi`.
To build against a newer core, `git -C core pull origin main` and commit the submodule.

## Security

Report vulnerabilities privately via **Security → Report a vulnerability**. See
[core's SECURITY.md](https://github.com/Quantex-Secure/certadel-agent-core/blob/main/SECURITY.md).

## License

[AGPL-3.0](LICENSE). Copyright © Quantex Secure.
