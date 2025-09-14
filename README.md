# IoT Tank Monitoring & Sharing App

Cross‑platform Flutter application for monitoring one or more liquid storage tanks (vertical / horizontal cylindrical or rectangular) over MQTT. It provides real‑time and snapshot volume calculations, grouping, sharing, and offline persistence.

## Core Features

### Tank Projects
Each "Project" represents a tank (or set of connected identical tanks) defined by:
- Tank geometry (vertical cylinder, horizontal cylinder, rectangular)
- Physical dimensions (height, diameter, length, width)
- Connected tank count (multiplies capacity & volume)
- Sensor type (submersible level vs. ultrasonic distance)
- MQTT connection (broker, port, topic, optional last‑will topic)
- Optional JSON payload parsing (index or key based, timestamp extraction)
- Optional control button (publish ON/OFF payloads with QoS/retain)
- Calibration multipliers and offsets

### Live Monitoring
- Real‑time subscription to an MQTT topic per project
- Automatic detection of stale connection state (Paused, Reconnecting, Stale)
- Presence indicator from a configured last‑will topic
- Timestamp display when payload provides time metadata

### Intelligent Volume & Percent Calculation
- Converts sensor readings to liquid level (meters) based on sensor type
- Computes liquid volume (L), empty volume, total volume, and percentage
- Accurate horizontal cylinder segment area math
- Supports multiple identical connected tanks by scaling volume

### Custom Liters Formula (Advanced)
- Optional user-defined formula to compute liters for heterogeneous connected tanks
- Variables (meters unless noted):
	- h (aka: level, lvl) – current measured liquid level (m)
	- H (aka: height) – tank total height (m)
	- L (aka: length, len) – tank length (m)
	- W (aka: width, wid) – tank width (m)
	- D (aka: diameter, dia) – tank diameter (m)
	- N (aka: count, tanks) – number of connected tanks (unitless)
- Operators: +, -, *, / and parentheses; implicit multiplication supported, e.g. 2(h+W) or (h)(W)
- Behavior when enabled:
	- Liquid liters = formula(h)
	- Total liters = formula(H)
	- Percent = liquid / total × 100
- Built-in Test formula preview in the editor to validate with an example level (shows result or a clear error)
- Examples:
	- Rectangular tank(s): N*L*W*h*1000
	- Vertical cylinder(s): N*3.14159*(D/2)*(D/2)*h*1000

#### AI helper (offline only)
- The app provides an offline helper that parses a short description and suggests a formula using variables (h,H,L,W,D,N). For mixed rectangular sizes, it prefers symbolic templates and may show an exact constant‑area alternative in the note.

Online AI has been removed. The editor no longer shows an online AI toggle or prompts for keys.

### Project & Group Management
- Create, rename, delete projects
- Create named groups, drag & drop projects between groups
- Group‑level aggregate: total capacity, total liquid, percent fill
- Improved deletion workflow: choose to ungroup or delete contained projects

### Data Persistence
- Local persistence via SharedPreferences with debounced writes
- Cached last known liquid & total liters for list screen aggregation

### Refresh & Snapshot
- Pull‑to‑refresh on project list triggers short‑lived MQTT connections to fetch retained values (snapshot update)
- One‑time automatic refresh when opening the list

### QR Share & Import
- Share a single project or multiple projects as a compressed Base64 QR payload
- Optionally include credentials (excluded by default for safety)
- Multi‑project QR encodes the group name so imports preserve original grouping
- Import via camera scan or gallery image selection (decodes QR from file)
- Conflict resolution dialog (replace / keep both / cancel)
 - Includes custom formula settings so imports preserve your configuration

### Theming & UI
- Light/Dark theme toggle
- Immersive full screen optional on first launch
- Adaptive layout scaling for tank dashboard metrics
- Marquee (scrolling) app bar title for long project names

## Dashboard Metrics Order
Current stat cards (first row, then second row):
1. Liquid % | Level (m) | Empty (m)
2. Total L | Liquid L | Empty L

## Security Considerations
- Credentials sharing is opt‑in per QR generation
- No remote storage; all configuration local unless explicitly shared via QR/text

## Tech Stack
- Flutter (Material 3)
- Provider (state management via `ProjectRepository` + `ThemeProvider`)
- MQTT client (`mqtt_client`)
- QR generation (`qr_flutter`) & scanning (`mobile_scanner`)
- Sharing (`share_plus`)
- Persistence (`shared_preferences`)

## Folder Highlights
`lib/` core application logic:
- `main.dart` – App entry + tank dashboard (MainTankPage)
- `project_model.dart` – Data model & JSON serialization
- `project_repository.dart` – Reactive state & persistence layer
- `project_list_page.dart` – Project/group management UI + pull refresh + import/share entry points
- `share_qr_page.dart` / `scan_qr_page.dart` – QR encode/decode UI flows
- `share_codec.dart` – Compression / Base64 envelope for project sharing

## Sharing Format (Simplified)
Envelope: `{ "t": "proj|multi", "v": 1, "d": <gzip+base64Url payload> }`
For multi-project payloads: optional marker `__IMPORT_GROUP_NAME__:<groupName>` enabling group recreation on import.

## Running Locally
Ensure Flutter SDK installed, then:
```bash
flutter pub get
flutter run
```

## Roadmap Ideas
- Optional cloud sync/export
- Role-based access or pin protection
- Historical charting (time‑series storage)
- Multi-broker monitoring dashboard view

## Contributing
Open a PR or issue with detailed description. Keep commits focused and prefer small, reviewable changes.

## License
Proprietary – All Rights Reserved.

This repository’s source is published for visibility and personal evaluation only. No rights are granted to copy, redistribute, publish, resell, or create derivative works without explicit written permission from the copyright holder (Wael Jihad Fakher). See `LICENSE` for full terms.

For commercial use, redistribution, or integration requests, contact: Wael Jihad Fakher.

---
Generated enhanced README to describe real functionality replacing default Flutter template.
