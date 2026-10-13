# WS0 – auditní skripty (pouze čtení)

Skripty **nic nemění** v tenantu. Spouští je výhradně administrátor (člověk), nikdy ne Claude.
Výstupy obsahují osobní údaje (UPN, jména, IP adresy) – patří do `reports/` (je v `.gitignore`)
a poté do zabezpečeného úložiště (viz kap. 6). Do Gitu se nikdy necommitují.

| Skript | Co zjišťuje | Modul | Oprávnění / role |
|---|---|---|---|
| `Get-WS0LicenseReport.ps1` | SKU, volné licence, servisní plány, licence a plány uživatelů, (volitelně poslední přihlášení) | Microsoft.Graph | Graph: `LicenseAssignment.Read.All`, `User.Read.All`, (`AuditLog.Read.All`) · role Global Reader |
| `Get-WS0MfaReport.ps1` | registrace MFA metod, správci bez MFA, výchozí zabezpečení, podmíněný přístup | Microsoft.Graph | Graph: `AuditLog.Read.All`, `Policy.Read.All`, `User.Read.All` · role Global Reader (nebo Reports Reader + Security Reader) |
| `Get-WS0PublicGroupsReport.ps1` | veřejné týmy a skupiny M365, skupiny bez vlastníka | Microsoft.Graph | Graph: `Group.Read.All` · role Global Reader |
| `Get-WS0SharingSettingsReport.ps1` | nastavení sdílení tenantu, SharePoint webů a OneDrive (odkazy „Kdokoli“, výchozí odkaz pro celou organizaci) | Microsoft.Online.SharePoint.PowerShell | role SharePoint Administrator |
| `Get-WS0SharingLinksReport.ps1` | vytvořené/použité odkazy „Kdokoli“ a „celá organizace“ z auditního logu | ExchangeOnlineManagement | role View-Only Audit Logs / Audit Logs |

## 1. Příprava pracovní stanice (jednorázově)

Doporučeno: Windows 10/11, **PowerShell 7.4+** pro Graph a Exchange, **Windows PowerShell 5.1** pro SharePoint.

```powershell
# PowerShell 7 (pwsh), jako běžný uživatel:
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser

# Windows PowerShell 5.1 (powershell.exe):
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser
```

Pokud je zakázané spouštění skriptů:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned` (jen pro aktuální okno).
Po stažení z Gitu případně `Get-ChildItem .\scripts\audit | Unblock-File`.

## 2. Účty a role

- Použijte **samostatný administrátorský účet** s MFA (ne běžný pracovní účet).
- Pro Graph skripty stačí **Global Reader**. Pro SharePoint skript je nutný **SharePoint Administrator**
  (Global Reader nestačí). Pro auditní log role **View-Only Audit Logs**.
- Pokud se role přiděluje přes PIM, aktivujte ji před spuštěním.

## 3. Souhlas (consent) – pozor, jde o změnu tenantu

Graph skripty se přihlašují přes aplikaci **Microsoft Graph Command Line Tools**. Pokud v tenantu ještě
nemá souhlas s danými oprávněními, Entra ID zobrazí výzvu k souhlasu:

- **Global Reader souhlas udělit nemůže** – výzvu musí schválit Global Administrator / Privileged Role
  Administrator / Cloud Application Administrator.
- Zaškrtnutí „Consent on behalf of your organization“ **je změna tenantu** (oprávnění pro enterprise
  aplikaci). Zapište ji do protokolu WS0 (kdo, kdy, jaká oprávnění). Oprávnění jsou pouze `*.Read.All`.
- Alternativa pro klienty s přísnou politikou: vlastní registrace aplikace jen se čtecími oprávněními
  (připraví WS1 – `scripts/identity`), pak `Connect-MgGraph -ClientId <app-id> -TenantId <tenant>`.

## 4. Spuštění – krok za krokem

```powershell
# 0) Přejděte do kořene repozitáře (jen lokální klon; nic se neposílá do Gitu)
cd C:\Git\Cleversystems

# --- PowerShell 7 (pwsh) ---
# 1) Licence a plány (s posledním přihlášením – vyžaduje Entra ID P1/P2; bez P1 vynechte přepínač)
.\scripts\audit\Get-WS0LicenseReport.ps1 -IncludeSignInActivity

# 2) MFA
.\scripts\audit\Get-WS0MfaReport.ps1

# 3) Veřejné týmy a skupiny
.\scripts\audit\Get-WS0PublicGroupsReport.ps1

# 4) Odkazy „Kdokoli“ / celá organizace z auditního logu (posledních 90 dní)
.\scripts\audit\Get-WS0SharingLinksReport.ps1 -UserPrincipalName <admin-UPN> -Days 90

# --- Windows PowerShell 5.1 (powershell.exe) ---
# 5) Nastavení sdílení SharePoint + OneDrive (název tenantu z URL https://<tenant>-admin.sharepoint.com)
.\scripts\audit\Get-WS0SharingSettingsReport.ps1 -AdminUrl https://<tenant>-admin.sharepoint.com -IncludeOneDrive
```

Poznámky:
- U klienta (multi-tenant přihlášení) přidejte ke Graph skriptům `-TenantId <domena>.onmicrosoft.com`.
  Hodnotu nikdy nezapisujte do souborů v repozitáři.
- Skript 5 u stovek webů / tisíců OneDrive běží desítky minut. Rychlý průchod: bez `-IncludeOneDrive`,
  případně `-SkipSiteDetail` (pak chybí úroveň sdílení jednotlivých webů).
- Skript 4: pokud hlásí vypnutý auditní log, nic nezapínejte – jde o nález do WS0 (zapnutí je změna tenantu).
- Každý skript končí hláškou `Hotovo. Nic nebylo změněno.` Chybu nebo varování zkopírujte do protokolu.

## 5. Kam se uloží výstupy

Výchozí složka: `<repo>\reports\<RRRR-MM-DD>_WS0\` (všechny skripty téhož dne do jedné složky).
Jinou složku zadáte parametrem `-OutputPath`. CSV jsou v UTF-8 s oddělovačem `;` (otevře český Excel).

| Soubor | Obsah |
|---|---|
| `licenses-skus.csv`, `licenses-sku-plans.csv` | předplatná, počty, plány v SKU |
| `users-licenses.csv`, `users-service-plans.csv` | licence a plány uživatelů |
| `mfa-registration.csv`, `mfa-admins-without-mfa.csv` | registrace MFA, kritické nálezy u správců |
| `mfa-security-defaults.json`, `mfa-conditional-access.csv` | vynucení MFA |
| `groups-m365.csv`, `groups-public.csv` | veřejné týmy/skupiny |
| `sharing-tenant.csv`, `sharing-sites.csv` | nastavení sdílení tenantu a webů |
| `links-audit-events.csv`, `links-audit-by-site.csv` | odkazy „Kdokoli“ / celá organizace z auditu |
| `*-summary.json` | souhrny pro zprávu WS0 |

## 6. Uložení a ochrana výstupů po auditu

1. Ověřte, že Git výstupy nevidí: `git status` nesmí ukazovat `reports/`.
2. Celou složku `reports\<datum>_WS0` přesuňte do **zabezpečené knihovny SharePoint Cleversystems**
   (doporučeno: projektový web klienta, knihovna „Audit WS0“, přístup jen řešitelský tým,
   citlivostní popisek „Důvěrné“, pokud je v tenantu nasazen). U auditu klienta po dohodě do úložiště klienta.
3. Lokální kopii po přesunu smažte.
4. Výstupy neposílejte e-mailem jako přílohu; sdílejte odkazem „Konkrétní lidé“.
5. Doba uchování: podle smlouvy s klientem (doplnit v šabloně akceptace WS0).

## Ověření syntaxe

Cmdlety, parametry a oprávnění ověřeny 2026-10-13 ze zdrojových souborů dokumentace Microsoft Learn
(repozitáře `microsoftgraph/microsoft-graph-docs-contrib`, `MicrosoftDocs/microsoftgraph-docs-powershell`,
`MicrosoftDocs/OfficeDocs-SharePoint-PowerShell`, `MicrosoftDocs/office-docs-powershell`).
Microsoft Learn MCP nebyl v pracovním prostředí dostupný – **před prvním ostrým během ověřit
odkazy v hlavičkách skriptů přes Learn MCP** (viz docs/STAV.md, K ověření).
Skripty byly otestovány jen syntakticky a proti simulovaným cmdletům s fiktivními daty, ne proti reálnému tenantu.
