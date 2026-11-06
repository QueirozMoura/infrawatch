# Screenshots

This folder is reserved for real screenshots of the **InfraWatch | System Overview** dashboard. No screenshots have been added yet: only captures taken from an actual running stack should be committed.

## Suggested captures

| File name | What to capture |
| --- | --- |
| `system-overview.png` | The whole dashboard in the normal state (no active alerts), time range "Last 15 minutes" |
| `alerts-firing.png` | The top alert row while `TargetDown` is firing (see "Simulating an outage" in the main README) |

## How to capture

1. Start the stack and open <http://127.0.0.1:3000>, then the dashboard.
2. For the firing capture, run `scripts/demo-service.sh stop`, wait about 90 seconds, take the screenshot, then run `scripts/demo-service.sh restore`.
3. Save the images here as PNG (keep each under ~1 MB if possible).
4. In the main `README.md`, replace the commented block under **Dashboard > Screenshots** with the image links.

## Before committing a screenshot

Check that it does not expose anything you do not want public: hostnames, local IP addresses, network interface names, usernames, or browser tabs and bookmarks. Crop the image if needed. The Grafana login page and the `.env` password must never appear.
