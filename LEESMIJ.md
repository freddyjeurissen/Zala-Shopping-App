# Zala - Boodschappen App – Android-app (testversie 0.1)

Made & protected by JEEMC² – Crypto & AI Security.

Deze map bevat de complete app als zelfstandige versie, los van claude.ai:

| Onderdeel | Wat het doet |
|---|---|
| `www/` | De app zelf (zelfde functies als v2), plus downloadpagina met QR-code |
| `www/backend.js` | Inloggen met e-mailcode en live synchroniseren via Supabase |
| `supabase/schema.sql` | Database met Row Level Security: je lijst is alleen zichtbaar voor je huishouden |
| `BOUWSTRAAT-build.yml` | Bouwt bij elke wijziging automatisch de APK en zet de website online (komt op GitHub als `.github/workflows/build.yml`, zie stap 2) |
| `capacitor.config.json`, `package.json` | Instellingen om van de web-app een Android-app te maken |
| `assets/` | App-icoon (mandje in rood-wit-groen) |

Eenmalig instellen kost ongeveer 20 minuten. Daarna gaat alles automatisch.

---

## Stap 1 – Supabase (database en inloggen)

1. Ga naar https://supabase.com, maak een gratis account en kies **New project**.
   - Naam: `boodschappen-zala`
   - Region: **Central EU (Frankfurt)**, voor de AVG
   - Kies een sterk databasewachtwoord en bewaar het in je wachtwoordmanager.
2. Open **SQL Editor > New query**, plak de inhoud van `supabase/schema.sql` en klik **Run**. Je ziet "Success".
3. **Eerst eigen mailserver koppelen.** Nieuwe gratis projecten mogen de mailtemplate pas aanpassen als er een eigen SMTP-server is ingesteld.
   Open **Authentication > Emails > SMTP Settings**, zet **Enable custom SMTP** aan en gebruik **Brevo** (gratis, 300 mails per dag):
   - Maak een account op brevo.com. Voeg onder *Senders, domains & dedicated IPs* je afzenderadres toe en verifieer het (beter: verifieer het hele domein met de DKIM- en DMARC-records).
   - Maak onder *SMTP & API > SMTP* een SMTP-key aan.
   - In Supabase: host `smtp-relay.brevo.com`, poort `587`, username = de *SMTP login* die Brevo toont, password = de SMTP-key (begint met `xsmtpsib-`), sender email = het geverifieerde adres, sender name `Zala - Boodschappen App`.
   - Gebruik **niet** `smtp.office365.com`: Microsoft heeft Basic Authentication voor SMTP AUTH in 2026 uitgeschakeld, en Supabase ondersteunt alleen gebruikersnaam plus wachtwoord. Je krijgt dan de foutmelding `{}` bij het inloggen.
   Daarna: open **Authentication > Emails > Templates**. Doe bij **Magic Link** én bij **Confirm signup** hetzelfde:
   - **Subject**: plak de inhoud van `supabase/email-subject.txt`
   - **Body / Message**: plak de inhoud van `supabase/email-template.html`
   - klik **Save**.
   De mail komt dan automatisch in de taal van de gebruiker (Nederlands, Duits, Engels of Hongaars). De app geeft die taal door bij het inloggen en bij het wisselen van taal; voor andere talen wordt het Engels.
   Zet onder **Authentication > URL Configuration** de **Site URL** op `https://<jouw-naam>.github.io/<repo>/`.
4. Controleer bij **Authentication > Sign In / Providers** dat **Email** aan staat.
5. Open **Project Settings > API** (of **Data API**) en noteer:
   - **Project URL** (bijv. `https://abcd1234.supabase.co`)
   - **anon public** key

   De anon key mag openbaar zijn: de beveiliging zit in de database-regels (RLS). Gebruik nooit de `service_role` key in de app.

> Komen codes niet aan? Kijk in je spam en in Brevo onder *Transactional > Logs*. Onder **Authentication > Rate Limits** kun je het aantal mails per uur verhogen.

## Stap 2 – GitHub (bouwen en downloaden)

1. Maak een gratis account op https://github.com als je die nog niet hebt.
2. Maak een nieuwe repository: **New repository**, naam `boodschappen-zala`, **Public**.
   - Public is nodig zodat je telefoon de APK zonder inloggen kan downloaden, en voor gratis GitHub Pages.
   - Er staan geen geheimen in de code. De Supabase-gegevens zet je in stap 3 als variabelen.
3. Zet de bestanden uit deze map in de repository. Het makkelijkst gaat dat met **GitHub Desktop** (https://desktop.github.com):
   *File > Add local repository* > kies deze map > *Publish repository*.
   Of via de opdrachtregel:

   ```
   git init
   git add .
   git commit -m "Zala - Boodschappen App 0.1"
   git branch -M main
   git remote add origin https://github.com/<jouw-naam>/boodschappen-zala.git
   git push -u origin main
   ```

4. Zet daarna het bouwbestand erbij. Dat kan alleen op GitHub zelf:
   in je repository **Add file > Create new file**, typ als naam precies `.github/workflows/build.yml`,
   plak de volledige inhoud van `BOUWSTRAAT-build.yml` uit deze map en klik **Commit changes**.

## Stap 3 – Koppelen

In je repository op GitHub:

1. **Settings > Secrets and variables > Actions > tabblad Variables > New repository variable**
   - `SUPABASE_URL` = je Project URL
   - `SUPABASE_ANON_KEY` = je anon public key
   - optioneel `VIDEO_URL` = link naar de uitlegvideo (bijv. YouTube). Leeg = de app meldt "video volgt binnenkort".
2. **Settings > Pages > Build and deployment > Source: GitHub Actions**
3. **Actions > Bouw app > Run workflow**. Het bouwen duurt 5 à 8 minuten.

Daarna staan klaar:

- de **APK** onder *Releases*: `https://github.com/<jouw-naam>/boodschappen-zala/releases/latest/download/boodschappen-zala.apk`
- de **downloadpagina met QR-code**: `https://<jouw-naam>.github.io/boodschappen-zala/download.html`
- de **webversie** (voor iPhone en pc): `https://<jouw-naam>.github.io/boodschappen-zala/`

## Stap 4 – Installeren op Android

1. Open de downloadpagina op je pc en scan de QR-code met je telefoon.
2. Open `boodschappen-zala.apk`. Sta "onbekende apps installeren" toe voor Chrome of je bestandsbeheer, en tik op **Installeren**.
3. Open de app, vul je e-mailadres in en daarna de code uit de mail.
4. Bij de route kies je **Mijn locatie**. Android vraagt dan één keer om toestemming voor je locatie.

Google Play Protect kan waarschuwen dat de app onbekend is. Dat is normaal voor een testversie buiten de Play Store: kies **Toch installeren**.

## Testers uitnodigen

Stuur testers de link naar de downloadpagina. Iedereen logt in met zijn eigen e-mailadres. Via **Instellingen > Huishouden** deel je de 6-letterige code, zodat je partner dezelfde lijst ziet.

## Updates

**Database-updates:** staat er in de map `supabase` een bestand `update-<datum>-….sql`, draai dat dan één keer in de Supabase **SQL Editor** (plakken > Run). Bij een nieuwe installatie is `schema.sql` genoeg; daar zitten alle updates al in.


Elke wijziging die je naar `main` pusht, levert automatisch een nieuwe APK op met een hoger versienummer. Installeer die over de oude heen; je gegevens blijven staan, want die zitten in Supabase. Gebruikt GitHub langer dan 7 dagen zijn opgeslagen ondertekensleutel niet, dan maakt hij een nieuwe. Dan moet je de app één keer verwijderen en opnieuw installeren. Voor de Play Store komt er later een vaste ondertekensleutel.

## Wat er anders is dan in de claude.ai-versie

- Inloggen met je eigen e-mailadres in plaats van een Claude-account.
- GPS werkt ("Mijn locatie").
- E-mail versturen opent je eigen mail-app met de lijst al ingevuld, in plaats van Outlook via Microsoft 365.
- Beveiliging per huishouden: alleen leden zien en wijzigen de lijst. Profielen (bijnaam en plaats) en ritten zijn zichtbaar voor andere ingelogde gebruikers.
- Zonder internet blijft de laatst geladen versie zichtbaar. Wijzigingen vereisen internet.

## Bekende beperkingen van deze testversie

- Afstanden zijn nog geschat (hemelsbreed ×1,3). Echte routes via OpenRouteService volgen in de MVP.
- Een contactnummer in je profiel kan door andere ingelogde gebruikers technisch worden opgevraagd. Vul dat alleen in als je dat goed vindt.
- De APK is een testversie, ondertekend met een ontwikkelsleutel.
