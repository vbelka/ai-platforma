# WS0 – Výchozí audit tenantu a připravenost na AI

> **Předpoklad:** Rozsah WS0 je odvozen z pokynu zadavatele, protože `docs/zadani.md` zatím v repozitáři chybí.
> Po doplnění zadání checklist porovnat a upravit (viz docs/STAV.md).

**Cíl:** zjistit výchozí stav licencí, identity a sdílení obsahu dřív, než se v tenantu zapne
Microsoft 365 Copilot / Copilot Studio. Hlavní riziko je **oversharing**: AI zpřístupní uživateli vše,
k čemu má oprávnění. Proto se sdílení auditu věnuje největší část WS0.

**Režim:** jen čtení. Žádné nastavení se ve WS0 nemění. Nálezy se řeší v dalších workstreamech.

| Pole | Hodnota |
|---|---|
| Tenant (pracovní označení, ne ID) | |
| Auditor | |
| Datum auditu | |
| Účet správce, role | |
| Úložiště výstupů (odkaz) | |

Stav: ☐ nezahájeno · ◐ probíhá · ☑ hotovo · ✖ nelze / N/A (uveďte důvod)

---

## A. Příprava

- ☐ A1 Je odsouhlasen rozsah auditu a pravidla nakládání s výstupy (citlivé údaje, úložiště, doba uchování).
- ☐ A2 Je k dispozici samostatný administrátorský účet s MFA a rolemi: Global Reader, SharePoint Administrator, View-Only Audit Logs.
- ☐ A3 Je ověřeno, zda je v tenantu udělen souhlas (consent) aplikaci Microsoft Graph Command Line Tools. Pokud ne, je určen schvalovatel a souhlas je zapsán do protokolu jako změna (`scripts/audit/README.md`, kap. 3).
- ☐ A4 Pracovní stanice má moduly Microsoft.Graph, ExchangeOnlineManagement a Microsoft.Online.SharePoint.PowerShell.
- ☐ A5 Klon repozitáře je aktuální a `git status` neukazuje složku `reports/`.

## B. Licence a plány – `Get-WS0LicenseReport.ps1`

- ☐ B1 Skript doběhl, existují `licenses-*.csv`, `users-*.csv` a `licenses-summary.json`.
- ☐ B2 Jsou zapsány všechny SKU (`SkuPartNumber`), zakoupené / přiřazené / volné licence a SKU ve stavu Warning nebo Suspended.
- ☐ B3 Je zjištěno, zda tenant má licence Microsoft 365 Copilot a kolik je volných.
      Souhrn hledá plány s „COPILOT“ v názvu. Jde jen o heuristiku, přesné názvy SKU **ověřit na Learn**.
- ☐ B4 Je zjištěna úroveň Entra ID (Free / P1 / P2). Podle ní se ve WS1 rozhoduje mezi výchozím zabezpečením a podmíněným přístupem.
- ☐ B5 Je zjištěno, zda nejsou vypnuté plány potřebné pro pilot (Exchange, SharePoint, OneDrive, Teams, Copilot). Sloupec `DisabledPlans`.
- ☐ B6 Jsou vypsáni zakázaní uživatelé s licencí (`FlagDisabledButLicensed`) jako úspora a chyby přiřazení (`AssignmentError`).
- ☐ B7 Pokud je k dispozici P1, jsou vypsáni neaktivní uživatelé s licencí (poslední přihlášení > 90 dní).
- ☐ B8 Je zapsáno, zda se licence přiřazují přes skupiny nebo přímo (`AssignedVia`). Doporučení pro WS1: skupiny.
- ☐ B9 Licenční závěry obsahují odkaz na Microsoft Learn a datum ověření. Ceny se uvádějí jen orientačně, s datem.

## C. MFA a přihlašování – `Get-WS0MfaReport.ps1`

- ☐ C1 Skript doběhl, existují `mfa-*.csv` a `mfa-*.json`.
- ☐ C2 **Kritické:** soubor `mfa-admins-without-mfa.csv` je prázdný. Pokud ne, nález okamžitě eskalovat vlastníkovi tenantu.
- ☐ C3 Je zapsán podíl členů s `IsMfaCapable = True`. Cíl pro pilot je 100 % uživatelů pilotu.
- ☐ C4 Je zjištěno, čím se MFA vynucuje: výchozí zabezpečení (`mfa-security-defaults.json`), zásady podmíněného přístupu ve stavu `enabled` s `RequiresMfa`, nebo nic.
- ☐ C5 Zásady ve stavu `enabledForReportingButNotEnforced` jsou zapsány jako nevynucené.
- ☐ C6 Ručně v Entra admin center je ověřeno, zda se nepoužívá starší „per-user MFA“ (cílově ho nahradit podmíněným přístupem). Skript tento stav nečte.
- ☐ C7 Jsou zapsány slabé metody (jen `mobilePhone`, `email`) a uživatelé bez metod.
- ☐ C8 Jsou zapsány výjimky v zásadách (`ExcludeUsers`, `ExcludeGroups`) a ověřeno, že jde jen o nouzové (break-glass) účty.
- ☐ C9 Existují alespoň 2 nouzové účty a je zapsáno, jak jsou chráněny. Ověřuje se ručně, předává se do WS1.

## D. Sdílení SharePoint a OneDrive – `Get-WS0SharingSettingsReport.ps1`

- ☐ D1 Skript doběhl, existují `sharing-tenant.csv`, `sharing-sites.csv` a `sharing-summary.json`.
- ☐ D2 Úroveň sdílení tenantu `SharingCapability` a OneDrive `OneDriveSharingCapability`. Hodnota `ExternalUserAndGuestSharing` znamená povolené odkazy **„Kdokoli“**.
- ☐ D3 Výchozí typ odkazu (`DefaultSharingLinkType`, `CoreDefaultShareLinkScope`, `OneDriveDefaultShareLinkScope`). Výchozí odkaz pro celou organizaci (`Internal` / `Organization`) je hlavní zdroj oversharingu před nasazením Copilota.
- ☐ D4 Expirace anonymních odkazů (`RequireAnonymousLinksExpireInDays`) a jejich oprávnění (`FileAnonymousLinkType`, `FolderAnonymousLinkType`: zobrazit / upravit).
- ☐ D5 Zobrazení deklarací „Everyone“ a „Everyone except external users“ (`ShowEveryone*Claim`). Pokud jsou zapnuté, lze web nebo soubor jedním krokem sdílet celé organizaci.
- ☐ D6 Seznam webů s `SharingCapability = ExternalUserAndGuestSharing` je předán vlastníkům webů k revizi.
- ☐ D7 Je zapsáno, kolik webů nemá citlivostní popisek (`SitesWithoutSensitivityLabel`).
- ☐ D8 Je zapsáno, zda je omezení domén (`SharingDomainRestrictionMode`) nastaveno.
- ☐ D9 Je ověřena dostupnost reportů SharePoint Advanced Management / Data access governance („Everyone except external users“, sdílení odkazy). Licenční podmínky **ověřit na Learn**. Pokud jsou dostupné, reporty se exportují ručně do složky WS0.

## E. Odkazy „Kdokoli“ a sdílení celé organizaci – `Get-WS0SharingLinksReport.ps1`

- ☐ E1 Je ověřeno, že sjednocený auditní log je zapnutý (`UnifiedAuditEnabled = true`). Pokud není, jde o nález. Zapnutí je změna tenantu a ve WS0 se neprovádí.
- ☐ E2 Skript doběhl za sledované období (výchozích 90 dní) a období je zapsané.
- ☐ E3 Počet vytvořených a použitých odkazů „Kdokoli“ (`AnonymousLink*`) a 10 webů s nejvíce událostmi (`links-audit-by-site.csv`).
- ☐ E4 Počet odkazů pro celou organizaci (`CompanyLink*`). Pokud je 0, ověřit, zda je název operace správný (**k ověření na Learn**).
- ☐ E5 Je zapsáno omezení metody: odkazy vytvořené před začátkem uchování auditu skript nevidí. Pro úplný inventář slouží bod D9.

## F. Veřejné týmy a skupiny – `Get-WS0PublicGroupsReport.ps1`

- ☐ F1 Skript doběhl, existují `groups-*.csv` a `groups-summary.json`.
- ☐ F2 Počet veřejných týmů a skupin (`groups-public.csv`). Jejich obsah je přístupný každému v organizaci, a tedy i Copilotu každého uživatele.
- ☐ F3 Seznam veřejných týmů je předán vlastníkům s otázkou „má být veřejný?“. Rozhodnutí se zapisuje, změny provádí až další WS.
- ☐ F4 Skupiny bez vlastníka (`FlagNoOwner`) jsou předány do WS1 (životní cyklus skupin).
- ☐ F5 Je zapsáno, kdo smí zakládat týmy a skupiny. Ověřuje se ručně v Entra admin center, skupiny, obecná nastavení.

## G. Výstup WS0

- ☐ G1 Souhrnná zpráva WS0: nálezy podle závažnosti (Kritické / Vysoké / Střední / Nízké), doporučení a vlastník.
- ☐ G2 Kritické nálezy (správci bez MFA, žádné vynucení MFA, odkazy „Kdokoli“ jako výchozí) jsou eskalovány před zahájením WS1.
- ☐ G3 Výstupy jsou přesunuty do zabezpečeného úložiště a lokální kopie smazány (`scripts/audit/README.md`, kap. 6).
- ☐ G4 Je aktualizován `docs/STAV.md`.
- ☐ G5 Akceptace WS0 klientem (šablona v `/templates`, zatím nepřipravena).
