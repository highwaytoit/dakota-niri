---
name: dakota-image
description: OCI layer assembly, boot testing, installer boundaries, VM work, and local OTA verification for Dakota images.
metadata:
  context7-sources:
    - /bootc-dev/bootc
---

# Dakota Image Integration

Use this skill when filesystem content crosses from BuildStream artifacts into OCI layers, or when testing and booting a local Dakota image.

## When to Use

- Modifying layer composition under `elements/oci/layers/`
- Changing post-install integration steps in `elements/oci/bluefin.bst`
- Running local VM boot tests (`just boot-test`, `just boot-fast`, `just boot-vm`)
- Validating transactional OTA updates or testing local registries (`references/local-ota.md`)
- Enforcing the installer boundary between Dakota and live installer tools

## When NOT to Use

- Building individual source packages or libraries → load `dakota-packaging`
- Packaging GNOME Shell extensions → load `dakota-extensions`
- Modifying GitHub Actions CI export or publication → load `dakota-ci`

## Core Process

1. **Layer Composition**: Compose layers with `kind: compose`. Build dependencies define layer contents.
2. **Order Post-Install Steps**:
   - `systemd-sysusers --root /layer`
   - `glib-compile-schemas /layer/usr/share/glib-2.0/schemas`
   - `dconf update /layer/etc/dconf/db`
   - `ldconfig -r /layer` (must run LAST before `build-oci`)
3. **Validate**: Run `just validate` to verify the composition graph.
4. **Boot Verification Ladder**:
   - Level 1: `just validate` (graph structure)
   - Level 2: `just lint` (bootc container structure)
   - Level 3: `just boot-test` (automated headless smoke test)
   - Level 4: `just boot-fast` (interactive ephemeral VM with virtiofs)
   - Level 5: Local OTA testing (`references/local-ota.md`) for hardware verification

## Invariants

- **Layer Element Kind**: All layer elements in `elements/oci/layers/` MUST use `kind: compose`. `kind: stack` produces empty artifacts and will break filesystem generation.
- **Linker Cache Load-Bearing Invariant**: `ldconfig -r /layer` must execute after all library updates and before `build-oci`. Any command altering `/usr/lib` must precede `ldconfig`.
- **Installer Separation**: Installer-specific Flatpaks or setup tools are purged on first boot via `files/firstboot/`. Installer UI changes belong in `projectbluefin/bootc-installer`, not Dakota.
- **Evidence Before Assertion**: Never assert boot success without executing one of the boot test recipes.
- **composefs-backed bootc**: Dakota's deployments are composefs, not classic
  OSTree checkouts. `/ostree/bootc` is a symlink to `../composefs/bootc`, there
  is no `/ostree/deploy`, and the staged deployment is finalized by
  `bootc-finalize-staged.service` (`ExecStop=/usr/bin/bootc
  composefs-finalize-staged`), never `ostree-finalize-staged.service`. Code and
  documentation that assume the ostree-named unit or deploy directory are wrong
  for this image.
- **Staged-deployment detection is privilege-split**: `bootc status` in any
  form opens the sysroot for write and fails for non-root callers, so no
  unprivileged process (desktop session, GNOME Shell extension, user service)
  can read deployment state from it. bootc starts
  `bootc-finalize-staged.service` the moment a deployment is queued for the
  next boot, and systemd unit state is readable on the system bus without
  privileges; query that unit instead. `/run/reboot-required` is an apt
  convention and is never written on bootc.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The element built, so the layer is fine." | Build success does not guarantee runtime inclusion or correct compose filters. |
| "I can put `ldconfig` anywhere in the post-install list." | If run before schema or dconf steps that copy libraries, `/etc/ld.so.cache` will be stale on boot. |
| "Booting in QEMU isn't necessary for a small change." | Desktop regression (e.g. GDM loop) only manifests at real boot. |
| "bootc is ostree underneath, so the ostree unit and paths apply." | Dakota deploys composefs. `ostree-finalize-staged.service` and `/ostree/deploy` do not exist here; `bootc-finalize-staged.service` and `/composefs/bootc` do. |
| "The extension can just shell out to `bootc status --format=json`." | It runs unprivileged and bootc refuses non-root callers, so the call always fails. A swallowed error then reads as "nothing staged" forever. |

## Red Flags

- `kind: stack` inside `elements/oci/layers/`
- New post-install commands inserted after `ldconfig -r /layer`
- Using `rpm-ostree` or `dnf` in layer integration scripts
- Modifying live installer code directly in Dakota instead of upstream repos
- Any unprivileged component (Shell extension, user unit, desktop script) calling `bootc status`
- Code keying reboot-pending state off `/run/reboot-required` on a bootc system
- References to `ostree-finalize-staged.service` or `/ostree/deploy` in Dakota code or docs

## Verification

- [ ] `just validate` passes
- [ ] `just lint` passes on the exported container
- [ ] `just boot-test` exits 0 (GDM desktop reaches ready state)
- [ ] `/etc/ld.so.cache` contains newly introduced shared libraries
- [ ] First-boot service cleanup scripts succeed

## References

- [`docs/oci-assembly.md`](../../../docs/oci-assembly.md)
- [`references/local-ota.md`](references/local-ota.md)
- [`elements/oci/`](../../../elements/oci/)
- [`files/firstboot/`](../../../files/firstboot/)
