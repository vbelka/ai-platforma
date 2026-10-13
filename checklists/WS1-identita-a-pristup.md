# WS1 – Identita a přístup (Entra ID) před zapnutím AI

> **Předpoklad:** Rozsah WS1 je odvozen ze struktury repozitáře (`scripts/identity`) a z výstupů WS0,
> protože `docs/zadani.md` zatím v repozitáři chybí. Po doplnění zadání checklist porovnat a upravit (viz docs/STAV.md).

**Cíl:** zajistit, aby k Microsoft 365 Copilot / Copilot Studio přistupovaly jen ověřené identity
s vynuceným MFA, se správně přiřazenými licencemi a s minimálními oprávněními správců.

**Režim:** WS1 už **mění tenant**. Každou změnu:
- provádí administrátor (člověk), nikdy ne Claude;
- skriptem z `scripts/identity` jen tehdy, když skript má výchozí režim čtení, parametr `-WhatIf` a v hlavičce popsaný dopad;
- zapisuje do protokolu změn (kdo, kdy, co, jak se vrátí zpět);
- u zásad podmíněného přístupu nejdřív nasazuje v režimu „Jen sestava“ (report-only).

**Vstup:** souhrnná zpráva WS0 a soubory v `reports/<datum>_WS0`.

| Pole | Hodnota |
|---|---|
| Tenant (pracovní označení, ne ID) | |
| Odpovědný administrátor | |
| Schvalovatel změn (klient) | |
| Okno pro změny | |

Stav: ☐ nezahájeno · ◐ probíhá · ☑ hotovo · ✖ nelze / N/A (uveďte důvod)

---

## A. Příprava a řízení změn

- ☐ A1 Kritické nálezy WS0 (C2, C4, G2) jsou vyřešeny nebo mají schválený plán.
- ☐ A2 Je schválen seznam změn WS1 včetně dopadu na uživatele (výzvy k registraci MFA, blokace starších protokolů).
- ☐ A3 Je připravena komunikace uživatelům: co se změní, kdy a jak zaregistrovat Microsoft Authenticator.
- ☐ A4 Je definována pilotní skupina uživatelů pro AI. Patří do ní jen uživatelé s licencí podle WS0 B3.

## B. Nouzové a správcovské účty

- ☐ B1 Existují 2 nouzové (break-glass) cloudové účty bez vazby na konkrétní osobu, se silnou metodou ověření (doporučeno FIDO2) a s monitorováním přihlášení. Postup **ověřit na Learn**.
- ☐ B2 Nouzové účty jsou vyloučeny ze zásad podmíněného přístupu, a to jako jediné výjimky.
- ☐ B3 Počet globálních správců je minimální (doporučení Microsoft **ověřit na Learn**). Ostatní mají role s nejnižšími oprávněními.
- ☐ B4 Správcovské role jsou na samostatných účtech, ne na účtech s poštou a Copilotem.
- ☐ B5 Pokud je k dispozici Entra ID P2, je pro správcovské role zavedena aktivace přes PIM. **Licenci ověřit na Learn.**
- ☐ B6 Všichni správci mají registrovanou silnou metodu MFA. Kontrola: opakovat `Get-WS0MfaReport.ps1`, soubor `mfa-admins-without-mfa.csv` musí být prázdný.

## C. Vynucení MFA

Podle úrovně Entra ID zjištěné ve WS0 B4 platí **jedna** z variant:

**Varianta 1 – Entra ID Free (bez P1): výchozí zabezpečení**
- ☐ C1 Výchozí zabezpečení (security defaults) je zapnuté. Ověří se opakováním `Get-WS0MfaReport.ps1`, `SecurityDefaultsEnabled = true`.
- ☐ C2 Je zapsáno omezení: bez výjimek a bez podmínek. Doporučení k upgradu na P1 obsahuje licenční odkaz na Learn a datum.

**Varianta 2 – Entra ID P1/P2: podmíněný přístup (CA)**
- ☐ C3 Výchozí zabezpečení je vypnuté až ve chvíli, kdy jsou připravené zásady CA. Obojí najednou nelze.
- ☐ C4 Zásada „MFA pro všechny uživatele“ (vyjma nouzových účtů): nejdřív Jen sestava, vyhodnocení, pak Zapnuto.
- ☐ C5 Zásada „Silnější MFA (síla ověřování odolná proti phishingu) pro správcovské role“.
- ☐ C6 Zásada „Blokovat starší ověřování“.
- ☐ C7 Zásada pro hosty: MFA a omezení přístupu k aplikacím.
- ☐ C8 Je zvážena zásada pro rizikové přihlášení / rizikového uživatele (vyžaduje P2, **ověřit na Learn**).
- ☐ C9 Starší „per-user MFA“ je vypnuto pro uživatele kryté zásadou CA (podle WS0 C6). Postup migrace **ověřit na Learn**.
- ☐ C10 Zásady jsou pojmenovány podle konvence (např. `CA001-All-MFA`) a exportovány jako záloha do zabezpečeného úložiště, ne do Gitu, pokud obsahují ID.

**Pro obě varianty**
- ☐ C11 Je nastavená zásada metod ověřování: povolen Microsoft Authenticator (s number matching) a FIDO2 / passkey. Omezení SMS a hlasu je posouzeno.
- ☐ C12 Je zapnutá registrační kampaň nebo jiný nástroj, který uživatele dovede k registraci Authenticatoru.
- ☐ C13 Kontrola: 100 % pilotní skupiny má `IsMfaCapable = True` (opakovat WS0 skript).

## D. Licence a skupiny

- ☐ D1 Licence Copilot (a další pro pilot) se přiřazují **přes skupinu** (group-based licensing). Dostupnost ve verzi Entra **ověřit na Learn**.
- ☐ D2 Skupina pilotu (např. `SG-AI-Pilot-Users`) je bezpečnostní skupina s určeným vlastníkem a dokumentovaným procesem přidávání.
- ☐ D3 Zakázaným uživatelům s licencí (WS0 B6) jsou licence uvolněny, po schválení klientem.
- ☐ D4 Chyby přiřazení licencí (WS0 B6) jsou vyřešeny.

## E. Hosté a externí identity

- ☐ E1 Je nastaveno, kdo smí zvát hosty (nastavení externí spolupráce). Hodnota je zapsaná.
- ☐ E2 Jsou zavedeny kontroly přístupu (access reviews) hostů, pokud to licence dovoluje (**ověřit na Learn**). Jinak je dohodnuta ruční revize, např. čtvrtletní.
- ☐ E3 Neaktivní hosté (> 90 dní) jsou zapsáni k odstranění. Odstranění schvaluje klient.

## F. Skupiny a týmy (příprava pro oversharing)

- ☐ F1 Je rozhodnuto, kdo smí zakládat skupiny a týmy M365 (podle WS0 F5).
- ☐ F2 Je zavedena zásada vlastnictví: každá skupina má aspoň 2 vlastníky. Řeší skupiny bez vlastníka z WS0 F4.
- ☐ F3 Je zavedena zásada vypršení (expiration) skupin M365. Licenční požadavek **ověřit na Learn**.
- ☐ F4 Veřejné týmy schválené k převodu na soukromé (WS0 F3) jsou převedeny se souhlasem vlastníků.
- ☐ F5 Je určena výchozí viditelnost nových skupin. Pozor: skupina M365 založená přes Graph bez určení viditelnosti je **Public** (Learn: resource group, visibility).

## G. Aplikace a souhlasy

- ☐ G1 Uživatelský souhlas (user consent) s aplikacemi třetích stran je omezen. Je zaveden workflow žádostí o souhlas správce.
- ☐ G2 Udělené souhlasy z WS0 (A3) jsou zapsány a zrevidovány.
- ☐ G3 Pro opakované audity je připravena registrace aplikace jen se čtecími oprávněními (`scripts/identity`, s `-WhatIf`).

## H. Výstup WS1

- ☐ H1 Opakovaný běh auditních skriptů WS0 potvrzuje cílový stav. Výsledky před a po se porovnají ve zprávě WS1.
- ☐ H2 Protokol změn je kompletní, včetně postupu návratu (rollback) pro každou změnu.
- ☐ H3 Je aktualizována provozní příručka: správa nouzových účtů, onboarding a offboarding uživatelů pilotu.
- ☐ H4 Je aktualizován `docs/STAV.md`.
- ☐ H5 Akceptace WS1 klientem (šablona v `/templates`, zatím nepřipravena).
