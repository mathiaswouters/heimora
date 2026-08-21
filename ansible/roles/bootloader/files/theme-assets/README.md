# GRUB theme provenance

`../theme/` is the **Vimix** variant of
[vinceliuice/grub2-themes](https://github.com/vinceliuice/grub2-themes),
GPL-3.0 (`LICENSE` in this directory).

Upstream ships a build repo, not an installable theme: `install.sh` assembles a
flat theme directory from `config/`, `common/`, `assets/` and `backgrounds/`.
We do that assembly once, by hand, and commit the result — running `install.sh`
on this machine would be wrong twice over. It defaults to `/boot/grub` (Fedora
uses `/boot/grub2`) and it edits `/etc/default/grub` and runs `grub-mkconfig`
itself, which is the `bootloader` role's job.

## What was kept

`theme-1080p.txt` and `theme-ultrawide.txt` are byte-identical, and `install.sh`
feeds the `ultrawide` screen variant the *1080p* icons, select pixmaps and info
bar. So the only thing that varies between our two supported resolutions is the
background, and one `theme.txt` covers both.

| Kept | Upstream source |
| --- | --- |
| `theme/theme.txt` | `config/theme-1080p.txt`, minus the `terminal-box` line |
| `theme/terminus-14.pf2`, `theme/unifont-16.pf2` | `common/` — the only two fonts `theme.txt` names |
| `theme/select_[cew].png` | `assets/assets-select/select-1080p/` |
| `theme/info.png` | `assets/info-1080p.png` |
| `theme/icons/` | `assets/assets-color/icons-1080p/`, trimmed to 13 |
| `background-1080p.jpg` | `backgrounds/1080p/background-vimix.jpg` |
| `background-ultrawide.jpg` | `backgrounds/ultrawide/background-vimix.jpg` |

Dropped: the other three theme variants, the 2k/4k/ultrawide2k backgrounds, the
unifont-24/32 and terminus-12/16/18 fonts (~18 MB of `.pf2` nothing references),
the white/whitesur icon sets, the SVG sources and render scripts, `install.sh`,
`flake.nix`, `banner.png` and `preview.png`. 28 MB down to under 3 MB.

`terminal-box: "terminal_box_*.png"` was removed from `theme.txt` because no
`terminal_box_*.png` exists anywhere in upstream — GRUB would silently fall back
to an unstyled terminal box regardless.

The 13 icons are what Fedora can actually ask for. `grub2-mkconfig` walks each
menu entry's `--class` list and takes the first `icons/<class>.png` that exists:
Fedora's Boot Loader Spec entries emit `--class fedora --class gnu-linux`,
`fwsetup` emits `--class efi`, and `unknown.png` catches everything else.
`windows.png` is there in case a dual boot ever shows up.

## Changing the look

- **Resolution** — `grub_theme_screen` in `ansible/group_vars/all.yml`
  (`1080p` or `ultrawide`). It picks the background *and* the matching
  `GRUB_GFXMODE`.
- **Another variant, or 2k/4k** — re-download upstream, then redo the table
  above with the variant and screen you want. Do not add
  `GRUB_GFXPAYLOAD_LINUX=keep`, which some GRUB theme guides suggest; it fights
  Fedora's simpledrm on the NVIDIA box.
- **A custom background** — drop in a JPEG matching your panel exactly and name
  it `background-<screen>.jpg`.
