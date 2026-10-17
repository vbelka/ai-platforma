# AI platforma – šablona Cleversystems

Referenční implementace AI platformy v tenantu Cleversystems a opakovatelná šablona nasazení u klientů
(architektura T1: Microsoft 365 + Copilot Studio, bez vlastní infrastruktury).

- Pravidla projektu: [CLAUDE.md](CLAUDE.md)
- Zadání: `docs/zadani.md` (zatím chybí – doplnit)
- Stav: [docs/STAV.md](docs/STAV.md)
- Checklisty: [checklists/](checklists/)
- Audit WS0 (jen čtení): [scripts/audit/README.md](scripts/audit/README.md)
- Registrace auditní aplikace (WS1): [scripts/identity/README.md](scripts/identity/README.md)

## Rychlý start – audit WS0 (spouští administrátor)

```powershell
cd C:\Git\ai-platforma
.\scripts\audit\Invoke-WS0Audit.ps1 -AdminUrl https://<tenant>-admin.sharepoint.com -UserPrincipalName <admin-UPN>
```
Výstupy včetně `WS0-souhrn.md` se uloží do `reports/<datum>_WS0/` (mimo Git).

## Vývoj

```powershell
pwsh -NoProfile -File tests/Invoke-AuditTests.ps1          # offline testy, fiktivní data
Invoke-ScriptAnalyzer -Path ./scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```
CI (GitHub Actions) spouští lint, testy a kontrolu, že v repozitáři nejsou výstupy auditů ani ID tenantů.
