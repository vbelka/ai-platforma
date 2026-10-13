# Stav projektu – AI platforma (šablona Cleversystems)

Poslední aktualizace: 2026-10-13
Struktura podle kap. 11 zadání: hotovo / zbývá / k ověření.

> **Blokující:** `docs/zadani.md` v repozitáři chybí (není v žádné větvi). Rozsah WS0 a WS1 je proto
> odvozen z pokynu zadavatele a z CLAUDE.md. Po vložení zadání revidovat checklisty a tento soubor.

## Hotovo

| Datum | Položka | Soubor |
|---|---|---|
| 2026-10-13 | Pravidla projektu | `CLAUDE.md` |
| 2026-10-13 | Struktura repozitáře (`checklists`, `scripts/{audit,identity,powerplatform,sql-demo}`, `solution`, `templates`, `calculator`) | – |
| 2026-10-13 | `/reports/` v `.gitignore`, ověřeno přes `git check-ignore` | `.gitignore` |
| 2026-10-13 | Checklist WS0 – výchozí audit | `checklists/WS0-vychozi-audit.md` |
| 2026-10-13 | Checklist WS1 – identita a přístup | `checklists/WS1-identita-a-pristup.md` |
| 2026-10-13 | Auditní skripty WS0 (jen čtení): licence a plány, MFA, nastavení sdílení SPO/OneDrive, odkazy „Kdokoli“ / celá organizace z auditu, veřejné týmy | `scripts/audit/*.ps1` |
| 2026-10-13 | Postup spuštění a uložení výstupů | `scripts/audit/README.md` |

Testy skriptů: kontrola syntaxe (PowerShell 7.4 parser) a běh proti simulovaným cmdletům s fiktivními
daty. **Neproběhl** běh proti reálnému tenantu.

## Zbývá

- [ ] Vložit `docs/zadani.md` a sladit s ním checklisty WS0/WS1 a číslování workstreamů.
- [ ] Spustit WS0 v tenantu Cleversystems (administrátor) a vyplnit checklist WS0.
- [ ] Souhrnná zpráva WS0 (šablona v `/templates`).
- [ ] Checklisty WS2–WS7.
- [ ] `scripts/identity`: registrace aplikace pro opakované audity (jen čtecí oprávnění, `-WhatIf`).
- [ ] `docs/` architektura T1 (Microsoft 365 + Copilot Studio) a provozní příručka.
- [ ] `/templates`: směrnice, registr AI systémů, akceptační protokoly WS0/WS1.
- [ ] `/calculator`: licenční kalkulačka (ceny jen orientačně, s datem ověření).
- [ ] Volitelně: inventář existujících sdílecích odkazů přes Graph (`driveItem` permissions, `link.scope = anonymous/organization`) pro vybrané weby. Doplňuje audit log, který nevidí starší odkazy.
- [x] AI platforma přesunuta z repozitáře CRM do samostatného repozitáře (2026-10-13).

## K ověření

| # | Co | Proč | Kde ověřit |
|---|---|---|---|
| V1 | Všechny cmdlety a oprávnění ve skriptech přes **Microsoft Learn MCP** | MCP nebyl v prostředí dostupný. Ověřeno ze zdrojových repozitářů dokumentace Learn na GitHubu (stav 2026-10-13). | odkazy v hlavičkách skriptů |
| V2 | Názvy operací `CompanyLinkCreated`, `CompanyLinkUsed`, `AnonymousLinkUpdated` | Ověřeny byly jen `AnonymousLinkCreated`/`Used`, `SecureLinkCreated` a `SharingSet`. | https://learn.microsoft.com/purview/audit-log-activities |
| V3 | Doba uchování auditního logu podle licence klienta | Ovlivňuje parametr `-Days`. | https://learn.microsoft.com/purview/audit-log-retention-policies |
| V4 | Licence pro SharePoint Advanced Management / Data access governance reporty | WS0 D9 | Learn – SharePoint Advanced Management |
| V5 | Přesné názvy SKU a plánů Microsoft 365 Copilot | Heuristika „COPILOT“ v `licenses-summary.json` | https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference |
| V6 | Zda `Get-SPOSite -Identity` stačí s rolí SharePoint Administrator bez role správce kolekce webů | Text dokumentace Get-SPOSite zmiňuje obojí. | Get-SPOSite (Learn) |
| V7 | Licenční tvrzení ve WS1 (P1 pro CA, P2 pro PIM a rizikové zásady, access reviews, expirace skupin) | Pravidlo projektu | Microsoft Entra licensing (Learn) |
| V8 | Tvrzení, že Copilot respektuje stávající oprávnění (zdůvodnění oversharingu) | Pravidlo projektu | Microsoft 365 Copilot – data, privacy and security (Learn) |
