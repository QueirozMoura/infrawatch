# Screenshots

Real screenshots of the **InfraWatch | System Overview** dashboard, used in the main README.

| File | What it shows |
| --- | --- |
| `system-overview.png` | The whole dashboard (13 panels) in the normal state, no active alerts, time range "Last 15 minutes" |
| `alerts-firing.png` | The same dashboard while `TargetDown` is firing after `demo-service` was stopped |

Both are 1700x1350 PNG images captured from a running stack on Fedora 44 with Firefox 150. They contain no PNG text or EXIF metadata. The only host-specific details visible are the network interface name and the `localhost:9101` instance label.

## Retaking or adding screenshots

1. Start the stack and open <http://127.0.0.1:3000>, then the dashboard (kiosk mode, `?kiosk`, hides the menus).
2. For the firing capture, run `scripts/demo-service.sh stop`, wait until the alert is `firing` (about 80 seconds), take the screenshot, then run `scripts/demo-service.sh restore` right away.
3. Save the images here as PNG (keep each under ~1 MB if possible) and reference them from the main `README.md`.

## Before committing a screenshot

Check that it does not expose anything you do not want public: hostnames, local IP addresses, usernames, or browser tabs and bookmarks. Crop the image if needed. The Grafana login page and the `.env` password must never appear.
