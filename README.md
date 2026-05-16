# 🛡️ GPO Duplicate Settings Analyzer

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Version](https://img.shields.io/badge/Version-2.0-orange)
![RSAT](https://img.shields.io/badge/Requires-RSAT%20GroupPolicy-informational)

> **Scan every GPO in your Active Directory domain, detect duplicate and conflicting settings, and generate an interactive HTML dashboard — all in a single PowerShell script.**

![GPO Duplicate Settings Analyzer Dashboard](screenshots/dashboard.png)

---

## 📋 Table of Contents

- [The Problem](#-the-problem)
- [The Solution](#-the-solution)
- [Features](#-features)
- [Supported Setting Types](#-supported-setting-types)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Usage](#-usage)
- [Parameters](#-parameters)
- [Report Overview](#-report-overview)
- [How It Works](#-how-it-works)
- [Understanding the Report](#-understanding-the-report)
- [Export](#-export)
- [FAQ](#-faq)
- [Contributing](#-contributing)
- [License](#-license)
- [Author](#-author)
- [Changelog](#-changelog)

---

## 🔥 The Problem

In mature Active Directory environments, **GPO sprawl** is a real and common challenge:

- Multiple IT administrators create GPOs over months and years
- New admins may not be aware of existing GPOs and create **new GPOs with the same settings**
- Since **"last applied GPO wins"**, earlier GPOs are silently overridden — and nobody notices
- Conflicting values across GPOs cause unpredictable behavior and hard-to-debug issues
- Over time, the number of GPOs grows, and nobody knows which setting lives where
- Troubleshooting becomes a manual, time-consuming exercise of clicking through GPMC

Without a tool like this, you would need to open each GPO individually in Group Policy Management Console, compare settings manually, and try to keep track of overlaps in a spreadsheet. For environments with 50, 100, or 200+ GPOs, that's simply not feasible.

---

## ✅ The Solution

**GPO Duplicate Settings Analyzer** is a single PowerShell script that:

1. **Enumerates all GPOs** in your domain
2. **Extracts every individual setting** from each GPO's XML report
3. **Groups settings by name and path** to identify duplicates
4. **Detects conflicts** where the same setting has different values across GPOs
5. **Generates an interactive HTML report** that makes it easy to review, search, filter, and export the findings

No agents. No modules to install (beyond built-in RSAT). No cloud dependency. Just run the script and open the report.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔍 **Full GPO XML Parsing** | Parses 10+ setting types from every GPO's XML report |
| 🔁 **Duplicate Detection** | Identifies settings configured in 2 or more GPOs |
| ⚠️ **Conflict Detection** | Flags settings with different values across GPOs |
| 🖥️ **Interactive HTML Dashboard** | Two-pane layout with left navigation and right detail view |
| 🔎 **Real-Time Search** | Search settings by name, category, or type — results update instantly |
| 🎛️ **Filter Buttons** | Filter by: All / Duplicates / Conflicts and Computer / User / Both |
| ☑️ **"Show Duplicates Only" Toggle** | Checkbox to instantly filter the list to only duplicate settings |
| 📥 **Export Duplicates to CSV** | One-click download of all duplicate settings for Excel review |
| 📂 **Collapsible Tree Navigation** | Settings grouped by Config Type → Setting Type → Category |
| 🏷️ **DUP / CONFLICT Badges** | Clear orange `DUP` and red `CONFLICT` pills on each setting |
| 💊 **Status Pills** | Color-coded GPO status: green (Enabled), red (Disabled), amber (Partial) |
| 🔗 **GPO Link Visibility** | Shows where each GPO is linked, with enabled/disabled tags |
| 📊 **Summary Statistics** | Cards showing Total GPOs, Unique Settings, Duplicates, Conflicts, Unlinked, Empty |
| ↔️ **Resizable Panes** | Drag the divider to resize the left and right panels |
| 📋 **Detail Table** | Per-setting breakdown: GPO Name, Value, Status, Links, Created, Modified dates |
| 🚀 **Zero External Dependencies** | Only requires the built-in RSAT GroupPolicy module |
| 🖥️ **Works Anywhere** | Runs on any domain-joined machine or domain controller |

---

## 📦 Supported Setting Types

The script parses the following GPO setting types from the XML reports:

| # | Setting Type | What It Captures |
|---|-------------|------------------|
| 1 | **Administrative Templates** | Policy name, state (Enabled/Disabled), category, description |
| 2 | **Registry Settings** | Key path, value name, data (Number/String) |
| 3 | **Account Policies** | Password, lockout, and Kerberos policy settings |
| 4 | **Security Options** | Interactive logon, network security, UAC, etc. |
| 5 | **User Rights Assignment** | Privilege assignments and their assigned members |
| 6 | **Audit Policy** | Audit subcategory names and their configured values |
| 7 | **Restricted Groups** | Group membership enforcement policies |
| 8 | **Event Log** | Log size, retention, and related settings |
| 9 | **Scripts** | Startup, shutdown, logon, and logoff scripts |
| 10 | **Preferences — Drive Maps** | Mapped drives (letter, path, action) |
| 11 | **Preferences — Printers** | Deployed printers and their properties |
| 12 | **Preferences — Registry** | Registry preference items |
| 13 | **Preferences — Shortcuts** | Desktop and Start Menu shortcuts |
| 14 | **Preferences — Scheduled Tasks** | Scheduled task definitions |
| 15 | **Preferences — Files/Folders** | File and folder operations |
| 16 | **Preferences — Data Sources** | ODBC data source configurations |
| 17 | **Preferences — Services** | Windows service startup and configuration |
| 18 | **Other / Generic** | Any additional setting types found in the XML |

---

## 📝 Requirements

| Requirement | Details |
|-------------|---------|
| **PowerShell** | Windows PowerShell 5.1 or PowerShell 7+ |
| **RSAT Module** | `GroupPolicy` module (included with RSAT) |
| **Machine** | Domain-joined workstation, member server, or domain controller |
| **Permissions** | Read access to Group Policy Objects in the domain |
| **OS** | Windows 10/11, Windows Server 2016/2019/2022/2025 |

### Installing RSAT (if not already present)

**Windows 10/11:**
```powershell
# Check if GroupPolicy module is available
Get-Module -ListAvailable GroupPolicy

# Install RSAT if needed (requires admin)
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
```

**Windows Server:**
```powershell
# Install via Server Manager or PowerShell
Install-WindowsFeature GPMC -IncludeManagementTools
```

---

## 📥 Installation

### Option 1: Clone the Repository

```bash
git clone https://github.com/yourusername/GPO-DuplicateAnalyzer.git
cd GPO-DuplicateAnalyzer
```

### Option 2: Download ZIP

1. Click the green **Code** button above
2. Select **Download ZIP**
3. Extract to a folder of your choice

### Option 3: Download Script Only

Download `GPO-DuplicateAnalyzer.ps1` directly and save it to any location.

---

## 🚀 Usage

### Basic Usage (Current Domain)

```powershell
.\GPO-DuplicateAnalyzer.ps1
```

This will:
- Scan all GPOs in your current domain
- Generate an HTML report in the current directory
- Automatically open the report in your default browser

### Specify a Domain

```powershell
.\GPO-DuplicateAnalyzer.ps1 -Domain "contoso.com"
```

### Custom Output Path

```powershell
.\GPO-DuplicateAnalyzer.ps1 -OutputPath "C:\Reports\GPO_Audit.html"
```

### Combine Parameters

```powershell
.\GPO-DuplicateAnalyzer.ps1 -Domain "corp.example.com" -OutputPath "D:\GPOReports\DuplicateCheck.html"
```

### Example Console Output

```
  +===========================================================+
  |       GPO Duplicate Settings Analyzer v2.0                |
  |       core365.cloud  |  blog.core365.cloud                |
  +===========================================================+

[*] Target domain: contoso.com
[*] Enumerating GPOs...
[*] Found 124 GPOs. Extracting settings...
[*] Extracted 3204 total setting instances.
[*] Unique settings : 2889
[*] Duplicates      : 315
[*] Conflicts       : 47
[*] Unlinked GPOs   : 12
[*] Empty GPOs      : 8
[*] Building report data...
[*] Generating HTML report...

  Report saved to: C:\Scripts\GPO_DuplicateReport_20260514_103045.html
```

---

## ⚙️ Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-OutputPath` | String | No | `GPO_DuplicateReport_<date>.html` in current directory | Full path for the output HTML report file |
| `-Domain` | String | No | Current user's domain (auto-detected) | Target Active Directory domain FQDN |

---

## 📊 Report Overview

The generated HTML report is a fully interactive, self-contained single-file dashboard.

### 🏗️ Layout Structure

```
┌─────────────────────────────────────────────────────────────┐
│  HEADER  — Domain name, generation date, GPO count          │
├─────────────────────────────────────────────────────────────┤
│  STATS   — Total GPOs │ Unique │ Duplicates │ Conflicts │ …│
├──────────────────┬──────────────────────────────────────────┤
│  LEFT PANE       │  RIGHT PANE                              │
│                  │                                          │
│  🔍 Search       │  Setting Name                            │
│  Filter buttons  │  Computer › Admin Templates › Category   │
│  ☑ Dup toggle   │                                          │
│  📥 Export CSV   │  ⚠️ Duplicate alert banner               │
│                  │                                          │
│  ▶ Category A    │  ┌─────────┬───────┬────────┬─────────┐ │
│    Setting 1     │  │GPO Name │Value  │Status  │Links    │ │
│    Setting 2 DUP │  │─────────┼───────┼────────┼─────────│ │
│  ▶ Category B    │  │GPO-1    │Enabled│●Active │OU=Corp  │ │
│    Setting 3     │  │GPO-2    │Disabl │●Partial│OU=Users │ │
│    ...           │  └─────────┴───────┴────────┴─────────┘ │
├──────────────────┴──────────────────────────────────────────┤
│  FOOTER  — Version, core365.cloud, blog.core365.cloud       │
└─────────────────────────────────────────────────────────────┘
```

### Left Pane

| Element | Description |
|---------|-------------|
| **Search Box** | Real-time search across setting names, categories, and types |
| **Filter Buttons** | `All` / `Duplicates` / `Conflicts` + `Both` / `Computer` / `User` |
| **Dup Toggle** | Checkbox: "Show duplicates only" — instantly filters the list |
| **Export Button** | Downloads all duplicate settings as a CSV file |
| **Settings Count** | Shows how many settings match the current filters |
| **Tree Navigation** | Collapsible groups: Config Type → Setting Type → Category |
| **Setting Items** | Each shows: config tag (`C`/`U`), name, `DUP`/`CONFLICT` pill, count badge |

### Right Pane

| Element | Description |
|---------|-------------|
| **Setting Name** | Full setting name as heading |
| **Breadcrumb** | Config Type → Setting Type → Category path |
| **Description** | Policy explanation (if available from GPO XML) |
| **Alert Banner** | Amber for duplicates, red for conflicts — with clear messaging |
| **Detail Table** | GPO Name, State/Value, GPO Status (pill), Config Section (pill), Linked To (tags), Created, Modified |

---

## ⚙️ How It Works

```
Step 1: Enumerate GPOs
    Get-GPO -All -Domain $Domain
    ↓
Step 2: Extract XML Reports
    Get-GPOReport -Guid $gpo.Id -ReportType Xml
    ↓
Step 3: Parse Settings
    XPath with local-name() to handle namespaces
    Switch on element LocalName for each setting type
    ↓
Step 4: Group & Detect
    Group-Object -Property SettingKey
    Count > 1 → Duplicate
    Different State values → Conflict
    ↓
Step 5: Generate Report
    Build JSON data → Embed in HTML template
    Interactive JS handles search, filter, detail view
    ↓
Step 6: Open Report
    Start-Process opens the HTML in your default browser
```

---

## 🎯 Understanding the Report

### What is a Duplicate?

A **duplicate** occurs when the **same setting** (identified by Config Type + Setting Type + Category + Setting Name) is configured in **two or more GPOs**.

> **Example:** "Minimum Password Length" configured in both `Default Domain Policy` and `Custom Password Policy`.

### What is a Conflict?

A **conflict** is a duplicate where the **values differ** across GPOs.

> **Example:** "Minimum Password Length" set to `8` in one GPO and `12` in another.

### Why Does This Matter?

In Group Policy, when multiple GPOs configure the same setting, the **last applied GPO wins** (based on link order, OU hierarchy, and enforcement). This means:

- ⚠️ **Duplicates with the same value** — Redundant configuration. Safe but cluttered.
- 🔴 **Conflicts with different values** — One GPO silently overrides the other. The "losing" GPO's setting is ignored without any warning or log entry.

### Color Coding

| Color | Meaning |
|-------|---------|
| 🟢 Green | Single GPO, no issues |
| 🟠 Orange / Amber | Duplicate — same setting in multiple GPOs |
| 🔴 Red | Conflict — different values across GPOs |
| 🔵 Blue | Computer configuration setting |
| 🟣 Purple | User configuration setting |

### Status Pills

| Pill | Meaning |
|------|---------|
| `All Enabled` (green) | GPO is fully enabled |
| `All Disabled` (red) | GPO is fully disabled |
| `Computer Settings Disabled` (amber) | Only user settings are active |
| `User Settings Disabled` (amber) | Only computer settings are active |

---

## 📥 Export

### Export Duplicates to CSV

Click the **"📥 Export Duplicates (CSV)"** button in the left pane toolbar to download a CSV file containing all duplicate settings.

**CSV Columns:**

| Column | Description |
|--------|-------------|
| Setting Name | The policy setting name |
| Category | Setting category (e.g., "Account Policies") |
| Setting Type | Type classification (e.g., "Security Settings") |
| Config Type | Computer or User |
| GPO Name | Name of the GPO containing this setting |
| State / Value | The configured value |
| GPO Status | Whether the GPO is enabled/disabled |
| Config Enabled | Whether the Computer/User config section is enabled |
| Linked To | Where the GPO is linked (with enabled status) |
| Created | GPO creation date |
| Modified | GPO last modified date |

The CSV file uses UTF-8 encoding with BOM for proper Excel compatibility.

---

## ❓ FAQ

### Q: Does this script make any changes to my GPOs?

**No.** The script is completely **read-only**. It only uses `Get-GPO` and `Get-GPOReport` — both are read operations. No GPOs are modified, created, or deleted.

### Q: How long does it take to run?

It depends on the number of GPOs. Typical timings:

| GPO Count | Approximate Time |
|-----------|-----------------|
| 50 GPOs | 1–2 minutes |
| 100 GPOs | 2–4 minutes |
| 200+ GPOs | 5–10 minutes |

The bottleneck is `Get-GPOReport` which queries each GPO individually. A progress bar is displayed during processing.

### Q: Can I run this from a non-domain-joined machine?

Not directly. The `GroupPolicy` module requires domain connectivity. You can run it from:
- A domain-joined workstation
- A domain controller
- A member server with RSAT installed
- A jump server / admin workstation

### Q: The report shows settings I don't recognise. What are they?

The script parses **all** setting types found in the GPO XML, including:
- Preferences (drive maps, printers, registry, shortcuts, scheduled tasks)
- Security settings (account policies, user rights, audit policy)
- Administrative templates
- Scripts

If a setting type is not specifically recognised, it falls back to a **generic parser** that extracts the name and value.

### Q: Can I schedule this to run automatically?

Yes! You can create a scheduled task to run the script periodically:

```powershell
# Example: Run weekly and save to a shared report folder
.\GPO-DuplicateAnalyzer.ps1 -OutputPath "\\FileServer\Reports\GPO_Weekly.html"
```

### Q: Does it work with PowerShell 7?

Yes. The script is compatible with both **Windows PowerShell 5.1** and **PowerShell 7+**. Ensure the `GroupPolicy` module is available in your PowerShell version (it may require the Windows Compatibility layer in PS7).

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Ideas for Contributions

- [ ] Additional setting type parsers (e.g., Windows Firewall rules, AppLocker)
- [ ] PDF export option
- [ ] Dark mode toggle in the HTML report
- [ ] GPO dependency/precedence visualization
- [ ] Comparison mode (diff between two GPOs)
- [ ] Multi-domain support in a single report

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2026 Antonio Rennvick Annoson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 👤 Author

**Antonio Rennvick Annoson**

- 🌐 Website: [core365.cloud](https://core365.cloud)
- 📝 Blog: [blog.core365.cloud](https://blog.core365.cloud)

---

## 📝 Changelog

### v2.0 (2026-05-14)

**Major UI overhaul inspired by community feedback and enterprise report best practices.**

- ✨ **Light left pane** — Replaced dark sidebar with clean white/light background matching the rest of the report
- 🏷️ **DUP / CONFLICT badges** — Clear orange and red pill labels on every duplicate/conflict setting
- ☑️ **"Show Duplicates Only" toggle** — Checkbox to instantly filter to just the duplicate settings
- 📥 **Export Duplicates to CSV** — One-click download of all duplicate settings for Excel/audit use
- 💊 **Status pills** — Color-coded GPO status indicators (Enabled/Disabled/Partial) in the detail table
- 🎨 **Improved duplicate visibility** — Subtle amber/red background tints on duplicate and conflict items
- 📊 **Category count badges** — Each collapsible category header now shows the setting count
- 🏗️ **Better detail table** — Amber row highlighting for multi-GPO settings
- 🧹 **Code cleanup** — Improved variable naming and structure

### v1.0 (2026-05-14)

**Initial release.**

- Full GPO XML parsing for 10+ setting types
- Duplicate and conflict detection
- Interactive two-pane HTML report
- Search, filter, and collapsible tree navigation
- Resizable panes
- Summary statistics cards
- GPO link visibility with enabled/disabled tags

---

<p align="center">
  <strong>⭐ If this tool helped you, please consider giving it a star! ⭐</strong>
</p>
