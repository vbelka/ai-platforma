# AI platforma – šablona Cleversystems
Účel: referenční implementace AI platformy v tenantu Cleversystems a opakovatelná šablona nasazení u klientů.
Zadání: docs/zadani.md (zdroj pravdy; při rozporu platí zadání).

## Pravidla (závazná)
- Dokumentace a checklisty česky; kód a názvy proměnných anglicky.
- Žádné přihlašovací údaje, tokeny, tenant ID klientů ani data klientů v repozitáři.
- /reports je v .gitignore (výstupy auditů mohou obsahovat citlivé údaje).
- Každý skript, který mění tenant: výchozí režim jen čtení, parametr -WhatIf, jasný popis dopadu v hlavičce.
  Skripty spouští výhradně administrátor (člověk), nikdy ne Claude.
- Před použitím cmdletu, API nebo licenčního tvrzení Microsoft ověř aktuální stav přes Microsoft Learn MCP a uveď odkaz.
- Licenční ceny Microsoft uvádět jen jako orientační s datem ověření.
- Demo pracuje jen s fiktivními daty.
- Nepoužívat AI Builder. Architektura T1 = Microsoft 365 + Copilot Studio, bez vlastní infrastruktury.

## Struktura
/docs (zadání, architektura, provozní příručka) · /checklists (WS0–WS7) ·
/scripts/{audit,identity,powerplatform,sql-demo} · /solution (exporty Copilot Studio) ·
/templates (směrnice, registr, akceptace) · /calculator · /reports (necommitovat)

## Stav
Udržuj docs/STAV.md: co je hotovo, co zbývá, co je k ověření (kap. 11 zadání).
