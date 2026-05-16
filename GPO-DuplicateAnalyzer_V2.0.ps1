<#
.SYNOPSIS
    Core365 GPO Duplicate Settings Analyzer v2.0 - Identifies duplicate and conflicting
    Group Policy settings across all GPOs in a domain and produces an interactive
    HTML report with export capability.

.DESCRIPTION
    Scans every GPO in Active Directory, extracts individual policy settings from
    XML reports, groups them by setting name/path, and generates an interactive
    two-pane HTML report.  The left pane lists every unique setting grouped by
    type and category.  The right pane shows which GPOs configure the selected
    setting, their values, link locations, and whether they conflict.

.PARAMETER OutputPath
    Path for the generated HTML report.
    Defaults to GPO_DuplicateReport_<date>.html in the current directory.

.PARAMETER Domain
    Target domain FQDN. If omitted the current user domain is used.

.NOTES
    +===================================================================+
    |   Core365 GPO Duplicate Settings Analyzer v2.0                            |
    |   Author  : Antonio Rennvick Annoson                              |
    |   Website : core365.cloud | blog.core365.cloud                    |
    +===================================================================+

    Requirements
      - Windows PowerShell 5.1+ or PowerShell 7+
      - RSAT Group Policy module  (GroupPolicy)
      - Run on a domain-joined machine or domain controller

.EXAMPLE
    .\GPO-DuplicateAnalyzer.ps1
    .\GPO-DuplicateAnalyzer.ps1 -OutputPath "C:\Reports\GPOReport.html"
    .\GPO-DuplicateAnalyzer.ps1 -Domain "contoso.com"
#>

#Requires -Modules GroupPolicy

[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$Domain
)

# -- Banner ----------------------------------------------------------------
Write-Host ""
Write-Host "  +===========================================================+" -ForegroundColor Cyan
Write-Host "  |       Core365 GPO Duplicate Settings Analyzer v2.0                |" -ForegroundColor Cyan
Write-Host "  |       core365.cloud  |  blog.core365.cloud                |" -ForegroundColor Cyan
Write-Host "  +===========================================================+" -ForegroundColor Cyan
Write-Host ""

# -- Resolve domain --------------------------------------------------------
if (-not $Domain) {
    try { $Domain = (Get-ADDomain).DNSRoot } catch { $Domain = $env:USERDNSDOMAIN }
}
Write-Host "[*] Target domain: $Domain" -ForegroundColor Green

if (-not $OutputPath) {
    $OutputPath = Join-Path $PWD ("GPO_DuplicateReport_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".html")
}

# -- Collect GPOs ----------------------------------------------------------
Write-Host "[*] Enumerating GPOs..." -ForegroundColor Yellow
$allGPOs = Get-GPO -All -Domain $Domain
$totalGPOs = $allGPOs.Count
Write-Host "[*] Found $totalGPOs GPOs. Extracting settings..." -ForegroundColor Yellow

# -- Helper ----------------------------------------------------------------
function Get-NodeText([System.Xml.XmlNode]$node, [string]$localName) {
    $xpath = '*[local-name()=''' + $localName + ''']'
    $child = $node.SelectSingleNode($xpath)
    if ($child) { return $child.InnerText.Trim() }
    return ""
}

# -- Process each GPO ------------------------------------------------------
$allSettings   = [System.Collections.ArrayList]::new()
$gpoLinkMap    = @{}
$gpoStatusMap  = @{}
$gpoMetaMap    = @{}
$settingId     = 0

for ($g = 0; $g -lt $totalGPOs; $g++) {
    $gpo = $allGPOs[$g]
    Write-Progress -Activity "Analysing GPOs" -Status "$($g+1) of $totalGPOs - $($gpo.DisplayName)" -PercentComplete (($g / $totalGPOs) * 100)

    try {
        [xml]$xml = Get-GPOReport -Guid $gpo.Id -ReportType Xml -Domain $Domain -ErrorAction Stop
    } catch {
        Write-Warning "Could not retrieve report for '$($gpo.DisplayName)': $_"
        continue
    }

    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("gp", "http://www.microsoft.com/GroupPolicy/Settings")

    $gpoName    = $gpo.DisplayName
    $gpoGuid    = $gpo.Id.ToString()
    $gpoCreated = $gpo.CreationTime.ToString("yyyy-MM-dd")
    $gpoMod     = $gpo.ModificationTime.ToString("yyyy-MM-dd")

    $compEnabled = $true; $userEnabled = $true
    switch ($gpo.GpoStatus) {
        "AllSettingsDisabled"      { $compEnabled = $false; $userEnabled = $false }
        "ComputerSettingsDisabled" { $compEnabled = $false }
        "UserSettingsDisabled"     { $userEnabled = $false }
    }
    $gpoStatusStr = $gpo.GpoStatus.ToString()

    # -- Links -------------------------------------------------------------
    $links = @()
    $linkNodes = $xml.SelectNodes('//*[local-name()=''LinksTo'']/*[local-name()=''Link'']')
    if (-not $linkNodes -or $linkNodes.Count -eq 0) {
        $linkNodes = $xml.SelectNodes('//*[local-name()=''Link'']')
    }
    foreach ($ln in $linkNodes) {
        $somPath    = (Get-NodeText $ln "SOMPath")
        $somEnabled = (Get-NodeText $ln "Enabled")
        $noOverride = (Get-NodeText $ln "NoOverride")
        if ($somPath) {
            $links += @{ Path = $somPath; Enabled = $somEnabled; NoOverride = $noOverride }
        }
    }
    if ($links.Count -eq 0) {
        $ltNodes = $xml.SelectNodes('//*[local-name()=''LinksTo'']')
        foreach ($lt in $ltNodes) {
            $somPath    = (Get-NodeText $lt "SOMPath")
            $somEnabled = (Get-NodeText $lt "Enabled")
            $noOverride = (Get-NodeText $lt "NoOverride")
            if ($somPath) {
                $links += @{ Path = $somPath; Enabled = $somEnabled; NoOverride = $noOverride }
            }
        }
    }

    $gpoLinkMap[$gpoGuid]   = $links
    $gpoStatusMap[$gpoGuid] = $gpoStatusStr
    $gpoMetaMap[$gpoGuid]   = @{ Name = $gpoName; Created = $gpoCreated; Modified = $gpoMod; CompEnabled = $compEnabled; UserEnabled = $userEnabled; Links = $links }

    # -- Parse extensions --------------------------------------------------
    foreach ($configType in @("Computer","User")) {
        $configXPath = '//*[local-name()=''' + $configType + ''']'
        $configNode  = $xml.SelectSingleNode($configXPath)
        if (-not $configNode) { continue }

        $configEnabledBool = if ($configType -eq "Computer") { $compEnabled } else { $userEnabled }
        $configEnabledStr  = if ($configEnabledBool) { "Enabled" } else { "Disabled" }

        $extNodes = $configNode.SelectNodes('*[local-name()=''ExtensionData'']')
        foreach ($ext in $extNodes) {
            $extBlock = $ext.SelectSingleNode('*[local-name()=''Extension'']')
            if (-not $extBlock) { continue }

            foreach ($child in $extBlock.ChildNodes) {
                if ($child.NodeType -ne 'Element') { continue }
                $localn = $child.LocalName

                $settingsToAdd = [System.Collections.ArrayList]::new()

                switch -Regex ($localn) {
                    "^Policy$" {
                        $name     = (Get-NodeText $child "Name")
                        $state    = (Get-NodeText $child "State")
                        $category = (Get-NodeText $child "Category")
                        $explain  = (Get-NodeText $child "Explain")
                        if ($name) {
                            [void]$settingsToAdd.Add(@{
                                SettingName = $name; Category = $category; State = $state
                                SettingType = "Administrative Templates"; Description = $explain; Details = ""
                            })
                        }
                    }
                    "^RegistrySetting$" {
                        $keyPath = (Get-NodeText $child "KeyPath")
                        $valNode = $child.SelectSingleNode('*[local-name()=''Value'']')
                        $valName = ""; $valData = ""
                        if ($valNode) {
                            $valName = (Get-NodeText $valNode "Name")
                            $valData = (Get-NodeText $valNode "Number")
                            if (-not $valData) { $valData = (Get-NodeText $valNode "String") }
                        }
                        $dispName = if ($valName) { "$keyPath\$valName" } else { $keyPath }
                        [void]$settingsToAdd.Add(@{
                            SettingName = $dispName; Category = "Registry"; State = $valData
                            SettingType = "Registry"; Description = ""; Details = "Key: $keyPath | Value: $valName = $valData"
                        })
                    }
                    "^Account$" {
                        foreach ($item in $child.ChildNodes) {
                            if ($item.NodeType -ne 'Element') { continue }
                            $name  = (Get-NodeText $item "Name")
                            $val   = (Get-NodeText $item "SettingNumber")
                            if (-not $val) { $val = (Get-NodeText $item "SettingBoolean") }
                            if ($name) {
                                [void]$settingsToAdd.Add(@{
                                    SettingName = $name; Category = "Account Policies"; State = $val
                                    SettingType = "Security Settings"; Description = ""; Details = ""
                                })
                            }
                        }
                    }
                    "^SecurityOptions$" {
                        foreach ($item in $child.ChildNodes) {
                            if ($item.NodeType -ne 'Element') { continue }
                            $dispNode = $item.SelectSingleNode('*[local-name()=''Display'']')
                            $name = ""; $val = ""
                            if ($dispNode) {
                                $name = (Get-NodeText $dispNode "Name")
                                $val  = (Get-NodeText $dispNode "DisplayString")
                                if (-not $val) { $val = (Get-NodeText $item "SettingNumber") }
                            }
                            if (-not $name) { $name = (Get-NodeText $item "SystemAccessPolicyName") }
                            if (-not $val)  { $val  = (Get-NodeText $item "SettingNumber") }
                            if ($name) {
                                [void]$settingsToAdd.Add(@{
                                    SettingName = $name; Category = "Security Options"; State = $val
                                    SettingType = "Security Settings"; Description = ""; Details = ""
                                })
                            }
                        }
                    }
                    "^UserRightsAssignment$" {
                        foreach ($item in $child.ChildNodes) {
                            if ($item.NodeType -ne 'Element') { continue }
                            $name = (Get-NodeText $item "Name")
                            $members = @()
                            foreach ($m in $item.SelectNodes('*[local-name()=''Member'']')) {
                                $mName = (Get-NodeText $m "Name")
                                if ($mName) { $members += $mName }
                            }
                            if ($name) {
                                [void]$settingsToAdd.Add(@{
                                    SettingName = $name; Category = "User Rights Assignment"; State = ($members -join ", ")
                                    SettingType = "Security Settings"; Description = ""; Details = ""
                                })
                            }
                        }
                    }
                    "^AuditSetting$" {
                        foreach ($item in $child.ChildNodes) {
                            if ($item.NodeType -ne 'Element') { continue }
                            $name = (Get-NodeText $item "SubcategoryName")
                            if (-not $name) { $name = (Get-NodeText $item "Name") }
                            $val  = (Get-NodeText $item "SettingValue")
                            if ($name) {
                                [void]$settingsToAdd.Add(@{
                                    SettingName = $name; Category = "Audit Policy"; State = $val
                                    SettingType = "Security Settings"; Description = ""; Details = ""
                                })
                            }
                        }
                    }
                    "^RestrictedGroups$" {
                        foreach ($item in $child.ChildNodes) {
                            if ($item.NodeType -ne 'Element') { continue }
                            $grpNode = $item.SelectSingleNode('*[local-name()=''GroupName'']')
                            $grpName = if ($grpNode) { (Get-NodeText $grpNode "Name") } else { "" }
                            if (-not $grpName -and $grpNode) { $grpName = $grpNode.InnerText }
                            if ($grpName) {
                                [void]$settingsToAdd.Add(@{
                                    SettingName = $grpName; Category = "Restricted Groups"; State = "Configured"
                                    SettingType = "Security Settings"; Description = ""; Details = ""
                                })
                            }
                        }
                    }
                    "^EventLog$" {
                        foreach ($item in $child.ChildNodes) {
                            if ($item.NodeType -ne 'Element') { continue }
                            $name = (Get-NodeText $item "Name")
                            $val  = (Get-NodeText $item "SettingNumber")
                            if ($name) {
                                [void]$settingsToAdd.Add(@{
                                    SettingName = $name; Category = "Event Log"; State = $val
                                    SettingType = "Security Settings"; Description = ""; Details = ""
                                })
                            }
                        }
                    }
                    "^Script$" {
                        $cmd   = (Get-NodeText $child "Command")
                        $stype = (Get-NodeText $child "Type")
                        $order = (Get-NodeText $child "Order")
                        if ($cmd) {
                            [void]$settingsToAdd.Add(@{
                                SettingName = $cmd; Category = "Scripts ($stype)"; State = "Order: $order"
                                SettingType = "Scripts"; Description = ""; Details = "Type: $stype, Order: $order"
                            })
                        }
                    }
                    "(DriveMapSettings|RegistrySettings|PrinterSettings|ShortcutSettings|ScheduledTasks|FilesSettings|FoldersSettings|DataSources|ServiceSettings)" {
                        $prefType = $localn -replace "Settings$", ""
                        foreach ($item in $child.ChildNodes) {
                            if ($item.NodeType -ne 'Element') { continue }
                            $props = $item.SelectSingleNode('*[local-name()=''Properties'']')
                            $name = ""
                            if ($props) {
                                $name = $props.GetAttribute("label")
                                if (-not $name) { $name = $props.GetAttribute("name") }
                                if (-not $name) { $name = $props.GetAttribute("path") }
                                if (-not $name) { $name = $props.GetAttribute("action") }
                            }
                            if (-not $name) { $name = (Get-NodeText $item "Name") }
                            if (-not $name) { $name = $item.GetAttribute("name") }
                            if (-not $name) { $name = "$prefType Preference Item" }
                            [void]$settingsToAdd.Add(@{
                                SettingName = $name; Category = $prefType; State = "Configured"
                                SettingType = "Preferences"; Description = ""; Details = ""
                            })
                        }
                    }
                    default {
                        $name = (Get-NodeText $child "Name")
                        if (-not $name) { $name = $child.LocalName }
                        $val = (Get-NodeText $child "State")
                        if (-not $val) { $val = (Get-NodeText $child "SettingValue") }
                        if (-not $val) { $val = "Configured" }
                        [void]$settingsToAdd.Add(@{
                            SettingName = $name; Category = "Other"; State = $val
                            SettingType = $child.LocalName; Description = ""; Details = ""
                        })
                    }
                }

                foreach ($s in $settingsToAdd) {
                    if (-not $s.SettingName) { continue }
                    $settingId++
                    $settingKey = $configType + "`t" + $s.SettingType + "`t" + $s.Category + "`t" + $s.SettingName
                    [void]$allSettings.Add([PSCustomObject]@{
                        Id            = $settingId
                        SettingKey    = $settingKey
                        SettingName   = $s.SettingName
                        Category      = $s.Category
                        State         = $s.State
                        ConfigType    = $configType
                        SettingType   = $s.SettingType
                        Description   = $s.Description
                        Details       = $s.Details
                        GPOName       = $gpoName
                        GPOGuid       = $gpoGuid
                        GPOCreated    = $gpoCreated
                        GPOModified   = $gpoMod
                        GPOStatus     = $gpoStatusStr
                        ConfigEnabled = $configEnabledStr
                        Links         = $links
                    })
                }
            }
        }
    }
}
Write-Progress -Activity "Analysing GPOs" -Completed

Write-Host "[*] Extracted $($allSettings.Count) total setting instances." -ForegroundColor Yellow

# -- Analyse duplicates ----------------------------------------------------
$grouped = $allSettings | Group-Object -Property SettingKey
$duplicateKeys = @{}
$conflictKeys  = @{}

foreach ($grp in $grouped) {
    if ($grp.Count -gt 1) {
        $duplicateKeys[$grp.Name] = $true
        $states = $grp.Group | Select-Object -ExpandProperty State -Unique
        if ($states.Count -gt 1) {
            $conflictKeys[$grp.Name] = $true
        }
    }
}

$uniqueSettings   = $grouped.Count
$duplicateCount    = ($duplicateKeys.Keys).Count
$conflictCount     = ($conflictKeys.Keys).Count
$unlinkedGPOs      = ($gpoMetaMap.Values | Where-Object { $_.Links.Count -eq 0 }).Count
$gposWithSettings  = ($allSettings | Select-Object -ExpandProperty GPOGuid -Unique).Count
$emptyGPOs         = $totalGPOs - $gposWithSettings

Write-Host "[*] Unique settings : $uniqueSettings" -ForegroundColor Cyan
Write-Host "[*] Duplicates      : $duplicateCount" -ForegroundColor $(if ($duplicateCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "[*] Conflicts       : $conflictCount" -ForegroundColor $(if ($conflictCount -gt 0) { "Red" } else { "Green" })
Write-Host "[*] Unlinked GPOs   : $unlinkedGPOs" -ForegroundColor $(if ($unlinkedGPOs -gt 0) { "Yellow" } else { "Green" })
Write-Host "[*] Empty GPOs      : $emptyGPOs" -ForegroundColor $(if ($emptyGPOs -gt 0) { "Yellow" } else { "Green" })

# -- Build JSON ------------------------------------------------------------
Write-Host "[*] Building report data..." -ForegroundColor Yellow

$jsonArray = [System.Collections.ArrayList]::new()
$idCounter = 0

foreach ($grp in ($grouped | Sort-Object Name)) {
    $idCounter++
    $first       = $grp.Group[0]
    $isDuplicate = $duplicateKeys.ContainsKey($grp.Name)
    $isConflict  = $conflictKeys.ContainsKey($grp.Name)

    $gpoList = [System.Collections.ArrayList]::new()
    foreach ($s in $grp.Group) {
        $linkList = [System.Collections.ArrayList]::new()
        foreach ($lnk in $s.Links) {
            [void]$linkList.Add(@{ path = $lnk.Path; enabled = $lnk.Enabled; noOverride = $lnk.NoOverride })
        }
        [void]$gpoList.Add(@{
            gpoName       = $s.GPOName
            gpoGuid       = $s.GPOGuid
            state         = $s.State
            gpoStatus     = $s.GPOStatus
            configEnabled = $s.ConfigEnabled
            created       = $s.GPOCreated
            modified      = $s.GPOModified
            details       = $s.Details
            links         = $linkList
        })
    }

    [void]$jsonArray.Add(@{
        id          = $idCounter
        settingKey  = $grp.Name
        settingName = $first.SettingName
        category    = $first.Category
        configType  = $first.ConfigType
        settingType = $first.SettingType
        description = $first.Description
        isDuplicate = $isDuplicate
        isConflict  = $isConflict
        gpoCount    = $grp.Count
        gpos        = $gpoList
    })
}

$jsonData = $jsonArray | ConvertTo-Json -Depth 5 -Compress

# -- Generate HTML ---------------------------------------------------------
Write-Host "[*] Generating HTML report..." -ForegroundColor Yellow

$reportDate = Get-Date -Format 'yyyy-MM-dd HH:mm'

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Core365 GPO Duplicate Settings Analyzer - $Domain</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Segoe UI',system-ui,-apple-system,sans-serif;background:#f1f5f9;color:#1e293b;display:flex;flex-direction:column;height:100vh;overflow:hidden;}

/* Header */
.header{background:linear-gradient(135deg,#1a237e,#283593);color:#fff;padding:18px 28px;flex-shrink:0;}
.header h1{font-size:22px;font-weight:600;letter-spacing:.3px;}
.header .sub{font-size:13px;opacity:.82;margin-top:4px;display:flex;gap:18px;flex-wrap:wrap;}

/* Stats */
.stats{display:flex;gap:12px;padding:14px 28px;flex-shrink:0;flex-wrap:wrap;background:#fff;border-bottom:1px solid #e2e8f0;}
.stat-card{flex:1;min-width:120px;padding:12px 16px;border-radius:10px;text-align:center;}
.stat-card .num{font-size:26px;font-weight:700;}
.stat-card .lbl{font-size:11px;text-transform:uppercase;letter-spacing:.6px;opacity:.85;margin-top:2px;}
.s-blue{background:#eff6ff;color:#1d4ed8;} .s-green{background:#f0fdf4;color:#15803d;}
.s-amber{background:#fffbeb;color:#b45309;} .s-red{background:#fef2f2;color:#b91c1c;}
.s-slate{background:#f8fafc;color:#475569;} .s-gray{background:#f9fafb;color:#6b7280;}

/* Main */
.main{display:flex;flex:1;overflow:hidden;}

/* Left Pane - LIGHT */
.left-pane{width:420px;min-width:300px;background:#ffffff;display:flex;flex-direction:column;border-right:1px solid #e2e8f0;flex-shrink:0;}
.search-box{padding:10px 12px;border-bottom:1px solid #e2e8f0;position:relative;}
.search-box input{width:100%;padding:8px 32px 8px 12px;border-radius:6px;border:1px solid #cbd5e1;background:#f8fafc;color:#1e293b;font-size:13px;outline:none;}
.search-box input:focus{border-color:#3b82f6;background:#fff;}
.search-box .clear-btn{position:absolute;right:18px;top:50%;transform:translateY(-50%);background:none;border:none;color:#94a3b8;cursor:pointer;font-size:16px;display:none;}

/* Toolbar */
.toolbar{display:flex;gap:4px;padding:8px 12px;border-bottom:1px solid #e2e8f0;flex-wrap:wrap;align-items:center;}
.toolbar .sep{width:1px;height:20px;background:#e2e8f0;margin:0 6px;}
.fbtn{padding:4px 10px;border-radius:4px;border:1px solid #cbd5e1;background:#fff;color:#64748b;cursor:pointer;font-size:11px;font-weight:500;transition:.15s;}
.fbtn.active{background:#3b82f6;color:#fff;border-color:#3b82f6;}
.fbtn:hover:not(.active){background:#f1f5f9;}

/* Toggle + Export row */
.toggle-row{display:flex;align-items:center;justify-content:space-between;padding:6px 12px;border-bottom:1px solid #e2e8f0;gap:8px;}
.toggle-label{display:flex;align-items:center;gap:6px;font-size:12px;color:#475569;cursor:pointer;user-select:none;}
.toggle-label input[type=checkbox]{accent-color:#f59e0b;width:15px;height:15px;cursor:pointer;}
.export-btn{padding:4px 12px;border-radius:4px;border:1px solid #cbd5e1;background:#fff;color:#475569;cursor:pointer;font-size:11px;font-weight:500;transition:.15s;white-space:nowrap;}
.export-btn:hover{background:#f1f5f9;border-color:#94a3b8;}

.settings-count{padding:6px 14px;font-size:11px;color:#94a3b8;border-bottom:1px solid #e2e8f0;background:#fafbfc;}

/* Settings list */
.settings-list{flex:1;overflow-y:auto;}
.cat-header{position:sticky;top:0;z-index:2;background:#f1f5f9;padding:8px 14px;font-size:12px;font-weight:600;color:#475569;cursor:pointer;display:flex;justify-content:space-between;align-items:center;user-select:none;border-bottom:1px solid #e2e8f0;}
.cat-header:hover{background:#e2e8f0;}
.cat-header .arrow{transition:transform .2s;font-size:10px;color:#94a3b8;}
.cat-header.collapsed .arrow{transform:rotate(-90deg);}
.cat-count{background:#e2e8f0;color:#64748b;padding:1px 7px;border-radius:8px;font-size:10px;font-weight:600;margin-left:6px;}
.cat-items.hidden{display:none;}

.setting-item{padding:9px 14px;border-bottom:1px solid #f1f5f9;cursor:pointer;display:flex;align-items:center;gap:8px;transition:background .12s;border-left:3px solid transparent;background:#fff;}
.setting-item:hover{background:#f8fafc;}
.setting-item.active{background:#eff6ff;border-left-color:#3b82f6;}
.setting-item.dup{border-left-color:#f59e0b;background:#fffdf7;}
.setting-item.conflict{border-left-color:#ef4444;background:#fef8f8;}
.setting-item.active.dup,.setting-item.active.conflict{background:#eff6ff;}
.setting-item .name{flex:1;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#1e293b;}

/* Tags & Badges */
.tag{display:inline-block;padding:2px 6px;border-radius:3px;font-size:10px;font-weight:600;line-height:1.3;}
.tag-c{background:#dbeafe;color:#1d4ed8;} .tag-u{background:#f3e8ff;color:#7c3aed;}
.badge{padding:2px 7px;border-radius:10px;font-size:10px;font-weight:700;}
.badge-ok{background:#f0fdf4;color:#16a34a;}
.badge-dup{background:#fef3c7;color:#d97706;}
.badge-conflict{background:#fee2e2;color:#dc2626;}
.dup-pill{padding:1px 6px;border-radius:3px;font-size:9px;font-weight:700;background:#fef3c7;color:#d97706;margin-left:2px;}
.conflict-pill{padding:1px 6px;border-radius:3px;font-size:9px;font-weight:700;background:#fee2e2;color:#dc2626;margin-left:2px;}

/* Right Pane */
.right-pane{flex:1;background:#f8fafc;overflow-y:auto;padding:28px 32px;}
.placeholder{display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;color:#94a3b8;}
.placeholder svg{width:64px;height:64px;margin-bottom:16px;opacity:.4;}
.placeholder p{font-size:15px;}
.detail-header h2{font-size:20px;font-weight:600;color:#1e293b;margin-bottom:4px;word-break:break-word;}
.breadcrumb{font-size:12px;color:#64748b;margin-bottom:12px;}
.breadcrumb span{margin:0 4px;}
.desc-box{background:#eff6ff;border-left:4px solid #3b82f6;padding:12px 16px;border-radius:6px;margin:12px 0;font-size:13px;color:#1e40af;}
.alert{padding:12px 16px;border-radius:8px;margin:10px 0;font-size:13px;display:flex;align-items:center;gap:8px;}
.alert-amber{background:#fffbeb;border:1px solid #fde68a;color:#92400e;}
.alert-red{background:#fef2f2;border:1px solid #fecaca;color:#991b1b;}
.alert svg{width:18px;height:18px;flex-shrink:0;}

/* Detail Table */
.detail-table{width:100%;border-collapse:collapse;margin-top:16px;font-size:13px;border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;}
.detail-table th{background:#f1f5f9;text-align:left;padding:10px 12px;font-weight:600;border-bottom:2px solid #e2e8f0;color:#475569;white-space:nowrap;}
.detail-table td{padding:10px 12px;border-bottom:1px solid #e2e8f0;vertical-align:top;background:#fff;}
.detail-table tr:hover td{background:#f8fafc;}
.detail-table tr.dup-row td{background:#fffbeb;}

/* Status pills */
.pill{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;}
.pill-green{background:#dcfce7;color:#166534;} .pill-red{background:#fee2e2;color:#991b1b;}
.pill-amber{background:#fef3c7;color:#92400e;} .pill-gray{background:#f1f5f9;color:#64748b;}

/* Link tags */
.link-tag{display:inline-block;padding:2px 8px;border-radius:4px;font-size:11px;margin:2px;}
.link-enabled{background:#dcfce7;color:#166534;}
.link-disabled{background:#fee2e2;color:#991b1b;}

/* Detail tag */
.detail-tag{display:inline-block;padding:3px 8px;border-radius:4px;font-size:11px;font-weight:600;}
.dt-c{background:#dbeafe;color:#1d4ed8;} .dt-u{background:#f3e8ff;color:#7c3aed;}

/* Divider */
.divider{width:4px;background:#e2e8f0;cursor:col-resize;flex-shrink:0;}
.divider:hover{background:#3b82f6;}

/* Footer */
.footer{background:#1e293b;color:#94a3b8;text-align:center;padding:10px;font-size:11px;flex-shrink:0;}
.footer a{color:#93c5fd;text-decoration:none;}
.footer a:hover{text-decoration:underline;}

/* Scrollbar */
.settings-list::-webkit-scrollbar,.right-pane::-webkit-scrollbar{width:6px;}
.settings-list::-webkit-scrollbar-thumb{background:#cbd5e1;border-radius:3px;}
.right-pane::-webkit-scrollbar-thumb{background:#cbd5e1;border-radius:3px;}
</style>
</head>
<body>

<!-- Header -->
<div class="header">
  <h1>&#128737; Core365 GPO Duplicate Settings Analyzer</h1>
  <div class="sub">
    <span>Domain: <strong>$Domain</strong></span>
    <span>Generated: <strong>$reportDate</strong></span>
    <span>GPOs scanned: <strong>$totalGPOs</strong></span>
  </div>
</div>

<!-- Stats -->
<div class="stats">
  <div class="stat-card s-blue"><div class="num">$totalGPOs</div><div class="lbl">Total GPOs</div></div>
  <div class="stat-card s-green"><div class="num">$uniqueSettings</div><div class="lbl">Unique Settings</div></div>
  <div class="stat-card s-amber"><div class="num">$duplicateCount</div><div class="lbl">Duplicate Settings</div></div>
  <div class="stat-card s-red"><div class="num">$conflictCount</div><div class="lbl">Conflicting Settings</div></div>
  <div class="stat-card s-slate"><div class="num">$unlinkedGPOs</div><div class="lbl">Unlinked GPOs</div></div>
  <div class="stat-card s-gray"><div class="num">$emptyGPOs</div><div class="lbl">Empty GPOs</div></div>
</div>

<!-- Main -->
<div class="main">
  <div class="left-pane" id="leftPane">
    <div class="search-box">
      <input type="text" id="searchInput" placeholder="Search settings...">
      <button class="clear-btn" id="clearBtn" onclick="clearSearch()">&times;</button>
    </div>
    <div class="toolbar">
      <button class="fbtn active" data-filter="all" onclick="setFilter(this,'type')">All</button>
      <button class="fbtn" data-filter="duplicates" onclick="setFilter(this,'type')">Duplicates</button>
      <button class="fbtn" data-filter="conflicts" onclick="setFilter(this,'type')">Conflicts</button>
      <div class="sep"></div>
      <button class="fbtn active" data-filter="both" onclick="setFilter(this,'config')">Both</button>
      <button class="fbtn" data-filter="Computer" onclick="setFilter(this,'config')">Computer</button>
      <button class="fbtn" data-filter="User" onclick="setFilter(this,'config')">User</button>
    </div>
    <div class="toggle-row">
      <label class="toggle-label"><input type="checkbox" id="dupToggle" onchange="render()"> Show duplicates only</label>
      <button class="export-btn" onclick="exportDuplicates()">&#128229; Export Duplicates (CSV)</button>
    </div>
    <div class="settings-count" id="settingsCount"></div>
    <div class="settings-list" id="settingsList"></div>
  </div>

  <div class="divider" id="divider"></div>

  <div class="right-pane" id="rightPane">
    <div class="placeholder" id="placeholder">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/></svg>
      <p>Select a setting from the left panel to view details</p>
    </div>
    <div id="detailContent" style="display:none"></div>
  </div>
</div>

<!-- Footer -->
<div class="footer">
  Core365 GPO Duplicate Settings Analyzer v2.0 &nbsp;|&nbsp; Generated by <a href="https://core365.cloud" target="_blank">core365.cloud</a> &nbsp;|&nbsp; <a href="https://blog.core365.cloud" target="_blank">blog.core365.cloud</a>
</div>

<script>
var DATA = $jsonData ;

var activeId = null;
var filterType = 'all';
var filterConfig = 'both';
var searchTerm = '';

function render() {
  var dupOnly = document.getElementById('dupToggle').checked;
  var items = DATA;
  if (filterType === 'duplicates' || dupOnly) items = items.filter(function(i){return i.isDuplicate;});
  if (filterType === 'conflicts') items = items.filter(function(i){return i.isConflict;});
  if (filterConfig !== 'both') items = items.filter(function(i){return i.configType === filterConfig;});
  if (searchTerm) {
    var q = searchTerm.toLowerCase();
    items = items.filter(function(i){return i.settingName.toLowerCase().indexOf(q)!==-1 || i.category.toLowerCase().indexOf(q)!==-1 || i.settingType.toLowerCase().indexOf(q)!==-1;});
  }

  document.getElementById('settingsCount').textContent = items.length + ' settings shown';

  var tree = {};
  items.forEach(function(i){
    var k1 = i.configType, k2 = i.settingType, k3 = i.category || 'General';
    if (!tree[k1]) tree[k1] = {};
    if (!tree[k1][k2]) tree[k1][k2] = {};
    if (!tree[k1][k2][k3]) tree[k1][k2][k3] = [];
    tree[k1][k2][k3].push(i);
  });

  var list = document.getElementById('settingsList');
  list.innerHTML = '';

  ['Computer','User'].forEach(function(cfg){
    if (!tree[cfg]) return;
    Object.keys(tree[cfg]).sort().forEach(function(stype){
      Object.keys(tree[cfg][stype]).sort().forEach(function(cat){
        var catItems = tree[cfg][stype][cat];
        var hdr = document.createElement('div');
        hdr.className = 'cat-header';
        hdr.innerHTML = '<span>' + esc(cfg + ' \u203A ' + stype + ' \u203A ' + cat) + '<span class="cat-count">' + catItems.length + '</span></span><span class="arrow">\u25BC</span>';
        hdr.onclick = function(){
          this.classList.toggle('collapsed');
          this.nextElementSibling.classList.toggle('hidden');
        };
        list.appendChild(hdr);

        var container = document.createElement('div');
        container.className = 'cat-items';
        catItems.forEach(function(i){
          var el = document.createElement('div');
          var cls = 'setting-item';
          if (i.isConflict) cls += ' conflict';
          else if (i.isDuplicate) cls += ' dup';
          if (i.id === activeId) cls += ' active';
          el.className = cls;
          el.setAttribute('data-id', i.id);
          el.onclick = function(){ showDetail(i.id); };

          var tagCls = i.configType === 'Computer' ? 'tag-c' : 'tag-u';
          var badgeCls = 'badge-ok';
          if (i.isConflict) badgeCls = 'badge-conflict';
          else if (i.isDuplicate) badgeCls = 'badge-dup';

          var extra = '';
          if (i.isConflict) extra = '<span class="conflict-pill">CONFLICT</span>';
          else if (i.isDuplicate) extra = '<span class="dup-pill">DUP</span>';

          el.innerHTML = '<span class="tag ' + tagCls + '">' + i.configType.charAt(0) + '</span>' +
            '<span class="name" title="' + esc(i.settingName) + '">' + esc(i.settingName) + '</span>' +
            extra +
            '<span class="badge ' + badgeCls + '">' + i.gpoCount + '</span>';
          container.appendChild(el);
        });
        list.appendChild(container);
      });
    });
  });
}

function statusPill(s) {
  if (!s) return '<span class="pill pill-gray">Unknown</span>';
  if (s === 'AllSettingsEnabled') return '<span class="pill pill-green">All Enabled</span>';
  if (s === 'AllSettingsDisabled') return '<span class="pill pill-red">All Disabled</span>';
  return '<span class="pill pill-amber">' + esc(s.replace(/([A-Z])/g, ' $1').trim()) + '</span>';
}

function configPill(s) {
  if (s === 'Enabled') return '<span class="pill pill-green">Enabled</span>';
  return '<span class="pill pill-red">Disabled</span>';
}

function showDetail(id) {
  activeId = id;
  var item = null;
  for (var x=0;x<DATA.length;x++){if(DATA[x].id===id){item=DATA[x];break;}}
  if (!item) return;

  document.getElementById('placeholder').style.display = 'none';
  var dc = document.getElementById('detailContent');
  dc.style.display = 'block';

  var tagCls = item.configType === 'Computer' ? 'dt-c' : 'dt-u';
  var html = '<div class="detail-header"><h2>' + esc(item.settingName) + '</h2></div>';
  html += '<div class="breadcrumb"><span class="detail-tag ' + tagCls + '">' + esc(item.configType) + '</span> <span>\u203A</span> ' + esc(item.settingType) + ' <span>\u203A</span> ' + esc(item.category) + '</div>';

  if (item.description) {
    html += '<div class="desc-box">' + esc(item.description) + '</div>';
  }
  if (item.isDuplicate && !item.isConflict) {
    html += '<div class="alert alert-amber"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2L1 21h22L12 2zm0 3.5L19.5 19H4.5L12 5.5zM11 10v4h2v-4h-2zm0 6v2h2v-2h-2z"/></svg> This setting is configured in <strong>&nbsp;' + item.gpoCount + ' GPOs&nbsp;</strong>\u2014 the last applied GPO wins and previous values are silently overridden.</div>';
  }
  if (item.isConflict) {
    html += '<div class="alert alert-red"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-1-13h2v6h-2zm0 8h2v2h-2z"/></svg> <strong>CONFLICT DETECTED:</strong>&nbsp;This setting has different values across ' + item.gpoCount + ' GPOs. The last applied GPO wins.</div>';
  }

  html += '<table class="detail-table"><thead><tr><th>GPO Name</th><th>State / Value</th><th>GPO Status</th><th>Config Section</th><th>Linked To</th><th>Created</th><th>Modified</th></tr></thead><tbody>';
  var isMulti = item.gpoCount > 1;
  item.gpos.forEach(function(g){
    var linkHtml = '';
    if (g.links && g.links.length) {
      g.links.forEach(function(l){
        var cls = (l.enabled === 'true' || l.enabled === 'True') ? 'link-enabled' : 'link-disabled';
        linkHtml += '<span class="link-tag ' + cls + '">' + esc(l.path) + '</span> ';
      });
    } else {
      linkHtml = '<span style="color:#94a3b8;font-style:italic">Not linked</span>';
    }
    var rowCls = isMulti ? ' class="dup-row"' : '';
    html += '<tr' + rowCls + '><td><strong>' + esc(g.gpoName) + '</strong></td><td>' + esc(g.state) + '</td><td>' + statusPill(g.gpoStatus) + '</td><td>' + configPill(g.configEnabled) + '</td><td>' + linkHtml + '</td><td>' + esc(g.created) + '</td><td>' + esc(g.modified) + '</td></tr>';
  });
  html += '</tbody></table>';
  dc.innerHTML = html;

  var allItems = document.querySelectorAll('.setting-item');
  for(var j=0;j<allItems.length;j++){
    if(parseInt(allItems[j].getAttribute('data-id'))===id) allItems[j].classList.add('active');
    else allItems[j].classList.remove('active');
  }
}

function setFilter(btn, group) {
  var btns = btn.parentElement.querySelectorAll('.fbtn');
  for(var b=0;b<btns.length;b++){
    if (group === 'type' && ['all','duplicates','conflicts'].indexOf(btns[b].getAttribute('data-filter'))!==-1) btns[b].classList.remove('active');
    if (group === 'config' && ['both','Computer','User'].indexOf(btns[b].getAttribute('data-filter'))!==-1) btns[b].classList.remove('active');
  }
  btn.classList.add('active');
  if (group === 'type') filterType = btn.getAttribute('data-filter');
  if (group === 'config') filterConfig = btn.getAttribute('data-filter');
  render();
}

function clearSearch() {
  document.getElementById('searchInput').value = '';
  document.getElementById('clearBtn').style.display = 'none';
  searchTerm = '';
  render();
}

function exportDuplicates() {
  var rows = [['Setting Name','Category','Setting Type','Config Type','GPO Name','State / Value','GPO Status','Config Enabled','Linked To','Created','Modified']];
  DATA.forEach(function(i){
    if (!i.isDuplicate) return;
    i.gpos.forEach(function(g){
      var linkStr = '';
      if (g.links && g.links.length) {
        var parts = [];
        g.links.forEach(function(l){ parts.push(l.path + ' (' + l.enabled + ')'); });
        linkStr = parts.join('; ');
      }
      rows.push([i.settingName, i.category, i.settingType, i.configType, g.gpoName, g.state, g.gpoStatus, g.configEnabled, linkStr, g.created, g.modified]);
    });
  });
  var csv = rows.map(function(r){
    return r.map(function(c){ return '"' + String(c||'').replace(/"/g,'""') + '"'; }).join(',');
  }).join('\r\n');
  var blob = new Blob(['\uFEFF' + csv], {type:'text/csv;charset=utf-8;'});
  var url = URL.createObjectURL(blob);
  var a = document.createElement('a');
  a.href = url;
  a.download = 'GPO_Duplicates_Export.csv';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function esc(s) { if (!s) return ''; var d = document.createElement('div'); d.textContent = s; return d.innerHTML; }

document.getElementById('searchInput').addEventListener('input', function() {
  searchTerm = this.value;
  document.getElementById('clearBtn').style.display = this.value ? 'block' : 'none';
  render();
});

(function() {
  var divider = document.getElementById('divider');
  var left = document.getElementById('leftPane');
  var startX, startW;
  divider.addEventListener('mousedown', function(e) {
    startX = e.clientX; startW = left.offsetWidth;
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
    e.preventDefault();
  });
  function onMove(e) { left.style.width = Math.max(250, Math.min(800, startW + e.clientX - startX)) + 'px'; }
  function onUp() { document.removeEventListener('mousemove', onMove); document.removeEventListener('mouseup', onUp); }
})();

render();
var firstDup = null;
for(var d=0;d<DATA.length;d++){if(DATA[d].isDuplicate){firstDup=DATA[d];break;}}
if (firstDup) showDetail(firstDup.id);
</script>
</body>
</html>
"@

# -- Write output ----------------------------------------------------------
$html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
Write-Host ""
Write-Host "  Report saved to: $OutputPath" -ForegroundColor Green
Write-Host ""

Start-Process $OutputPath
