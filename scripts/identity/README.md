# WS1 – identita: skripty

| Skript | Co dělá | Mění tenant? |
|---|---|---|
| `New-WS0AuditApp.ps1` | Registrace vlastní aplikace Entra ID pro opakované audity WS0 (jen delegovaná čtecí oprávnění, bez tajemství) | **Ano, jen s `-Apply`** |

Skripty spouští výhradně administrátor (člověk). Výchozí režim je vždy jen čtení (plán).

## New-WS0AuditApp.ps1 – postup

1. **Plán (nic nemění)** – PowerShell 7, role Global Reader:
   ```powershell
   cd C:\Git\ai-platforma
   .\scripts\identity\New-WS0AuditApp.ps1
   ```
   Vypíše oprávnění a co by vytvořil. Pokud aplikace se stejným názvem existuje, nic nenavrhne.
2. **Kontrola změn** – role Application Administrator nebo Cloud Application Administrator:
   ```powershell
   .\scripts\identity\New-WS0AuditApp.ps1 -Apply -WhatIf
   ```
3. **Provedení** – zapsat do protokolu změn WS1 (kdo, kdy, co):
   ```powershell
   .\scripts\identity\New-WS0AuditApp.ps1 -Apply
   ```
   Před každou změnou se skript zeptá. Na konci vypíše AppId – **nezapisujte ho do repozitáře**.
4. **Souhlas správce** (ručně, Global Administrator nebo Privileged Role Administrator):
   Entra admin center → Identita → Aplikace → Registrace aplikací → aplikace → Oprávnění rozhraní API →
   Udělit souhlas správce pro organizaci.
5. **Audit s vlastní aplikací:**
   ```powershell
   .\scripts\audit\Invoke-WS0Audit.ps1 -ClientId <AppId> -TenantId <domena>.onmicrosoft.com -AdminUrl ... -UserPrincipalName ...
   ```

**Návrat zpět:** Entra admin center → Registrace aplikací → aplikace → Odstranit.
Odstraněná aplikace zůstává 30 dní v koši (lze obnovit).
