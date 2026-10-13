# Wertweit

Ein nativer iPhone-Reise- und Währungsrechner mit SwiftUI. Die App zeigt Umrechnung, grobe Kaufkraft-Richtwerte, Gebührenvergleiche und echte historische Referenzdaten.

## In Xcode starten

1. Öffne `Kursklar.xcodeproj` in Xcode.
2. Wähle das Schema `Kursklar` und einen iPhone-Simulator oder ein verbundenes iPhone. Der App-Name auf dem Gerät ist `Wertweit`.
3. Starte mit `Cmd+R`.

Die App ist auf Hochformat ausgelegt und unterstützt iOS 15 oder neuer, einschließlich iPhone 7. Auf diesem Mac ist derzeit ein iPhone-17-Simulator installiert; ein iPhone-7-Simulator ist nicht vorhanden.

Die iPhone-App benötigt ein Supabase-Auth-Konto mit E-Mail-Adresse und Passwort. Favoriten, Kursalarme und zuletzt geladene Wechselkurse bleiben lokal auf dem Gerät und werden nicht zwischen Geräten synchronisiert. In der App kann ein Konto gelöscht werden.

Wechselkurse, historische Referenzdaten und die Währungsliste werden über `api.frankfurter.dev` geladen. Der Dienst stellt Referenzkurse der EZB bereit; die App ist kein offizielles Produkt der EZB. Ein gespeicherter letzter Kurs kann ohne Internet verwendet werden und wird in der App als gespeichert gekennzeichnet.

Enthalten sind der Währungsrechner, Reise-Kaufkraftschätzungen für ausgewählte Länder, Trinkgeld- und Tagesbudget-Richtwerte, Gebühren- und Kursvergleich, Rückwärtsrechnung, einfache lokale natürlichsprachliche Eingabe, historische Kursdiagramme, Mehrfachwährungsanzeige und lokal gespeicherte Favoriten/Kursalarme. Kursalarme werden beim erfolgreichen Abruf der jeweiligen Ausgangswährung geprüft. Wird der Zielkurs erreicht, erscheint eine iOS-Gerätebenachrichtigung und eine Meldung in der App; der Alarm wird entfernt. Die App fragt beim Anlegen eines Kursalarms nach der Benachrichtigungserlaubnis. Es gibt keine Hintergrundüberwachung und keine Server-Push-Mitteilungen; der Kursalarm kann daher erst beim nächsten Kursabruf auslösen. Reise- und Preisangaben sind manuelle Schätzungen, werden nicht live abgerufen oder laufend geprüft und können abweichen.

## Abo-Entwurf

Der Währungsrechner bleibt kostenlos. Gratis sind außerdem die Umrechnung im Reisetab, der Gebühren-Simulator und ein 7-Tage-Kursverlauf. Pro erweitert die Reiseansicht um Beispielpreise, Budgets und Trinkgeld; schaltet Kursvergleich, Rückwärtsrechnung und Texteingabe frei; und bietet längere Verläufe, Mehrfachwährungen, Favoriten und Kursziele. Preisvorschlag für App Store Connect: 1,99 € pro Monat oder 14,99 € pro Jahr. Die App zeigt die von Apple lokalisierten Store-Preise an.

StoreKit 2 ist integriert: Kauf, Transaktionsprüfung, Abo-Berechtigung, Wiederherstellung und Abo-Änderungen. Produkt-IDs: `de.wertweit.app.pro.monthly` (automatisch verlängernd, 1 Monat) und `de.wertweit.app.pro.yearly` (automatisch verlängernd, 1 Jahr). Lege beide in derselben Abo-Gruppe `Wertweit Pro` in App Store Connect an und konfiguriere für beide ein 7-tägiges kostenloses Einführungsangebot. Apple bestimmt die Testberechtigung; pro Abo-Gruppe kann ein Kunde nur ein Einführungsangebot einlösen.

Für lokale Tests ist `WertweitPro.storekit` mit beiden Produkt-IDs und Preis `0` eingerichtet und im Xcode-Schema **Wertweit Pro Test** für **Run** ausgewählt. Damit lassen sich Kauf, Transaktionsprüfung und Pro-Freischaltung ohne Abbuchung im Simulator oder bei einem direkt aus Xcode gestarteten Gerät testen. Diese lokalen Testprodukte sind **nicht** in App Store Connect und funktionieren nicht in TestFlight oder einer veröffentlichten App. Für echte Nutzer müssen die Produkte in App Store Connect angelegt werden; dort muss ein regulärer Preis mit einem kostenlosen Einführungsangebot (z. B. 7 Tage) eingerichtet sein. Digitale Funktionen werden über Apples In-App Purchase abgerechnet; eigene Karteneingaben oder ein externer Checkout sind nicht vorgesehen. Das Wertweit-Konto ist vom Apple Account für die Abrechnung getrennt.

Der Adminbereich kann zusätzlich Überschriften und erläuternde Angebotstexte der Pro-Seite bearbeiten. Diese Texte ändern ausdrücklich nicht den Preis, die Laufzeit oder eine bestehende Apple-Abbuchung; Apple-Produktpreise werden weiterhin aus StoreKit geladen.

Der Menüpunkt **Test-Benachrichtigung** fordert bei Bedarf die iOS-Berechtigung an und plant eine lokale Testmeldung. Das prüft die Anzeige auf dem Gerät, verschickt aber keine Nachricht vom Supabase-Server. Dafür wären zusätzlich eine APNs-Konfiguration und sichere Versand-Zugangsdaten nötig.

## Supabase und Adminbereich

Die iPhone-App verwendet Supabase Auth/REST-Endpunkte direkt mit `URLSession`; langlebige Refresh-Tokens liegen ausschließlich in der iOS-Keychain. Das Admin-Web verwendet den Supabase-JavaScript-Client. `website/admin.html` bietet nach dem Login getrennte Seiten für Dashboard, Personen, Datenbank, Support, Einstellungen, App-Rechnungen, Kunden und private Verkäufe. „Personen“ zeigt einzelne App-Konten und führt zur Personenakte; „Datenbank“ enthält die Kontentabelle sowie Einladungen und Kontoverwaltung. Die Personenakte bündelt Kontostatus, manuelle Admin-Pro-Freigabe, gespeicherte App-Starts, Supportverläufe, interne Hinweise im oberen Aktenbereich und – sofern die E-Mail übereinstimmt – App-Rechnungen. Fehlende Namen werden nicht als Platzhalter angezeigt. Die Aktivitätshistorie umfasst nur tatsächlich erfasste App-Starts, keine vollständige Klick- oder Funktionshistorie. Interne Personen- und Ticketnotizen sind nur für Admins verfügbar und getrennt von öffentlichen Supportnachrichten bearbeitbar und löschbar. Der Adminbereich verwaltet außerdem Nutzer, Einladungen, Sperren, App-Wartung und Angebotstexte. App-/Geschäftsrechnungen haben einen wiederverwendbaren Produkt-/Leistungskatalog und eine manuell gepflegte Kundengruppe „Ohne Pro“ oder „Mit Pro“; diese Zuordnung wird nicht mit Apple-Abos synchronisiert. Neue Geschäftsrechnungen verwenden den konfigurierten Kleinunternehmerhinweis nach § 19 UStG und weisen keine Umsatzsteuer aus. Bitte prüfe, ob diese Einstellung zu deiner steuerlichen Situation passt. Die fortlaufende Rechnungsnummer wird in der Datenbank vergeben. Rechnungen bleiben als strukturierte Daten mit unveränderlichem Kunden- und Absenderschnappschuss im Supabase-Archiv; sie können gesucht, gefiltert und jederzeit erneut als A4-PDF gedruckt oder gespeichert werden. Der Rechnungsdruck verwendet einen formellen Briefkopf mit Empfänger-, Rechnungs- und Zahlungsdaten. Bei vorhandener E-Mail-Adresse öffnet „E-Mail vorbereiten“ das lokale Mailprogramm mit Empfänger, Betreff und Nachricht; der PDF-Beleg muss dort manuell angehängt werden. Es wird kein E-Mail-Versanddienst für diese Funktion verwendet. Private Verkäufe sind separat als private Verkaufsbelege gespeichert und werden nicht in die App-/Geschäftsrechnungen oder deren Kundenkonten gemischt. Die privaten Belege weisen keine Umsatzsteuer aus; sie sind keine steuerliche Einordnung oder Beratung. Kunden- und Rechnungsdaten sind nur über serverseitig geprüfte Admin-Aktionen erreichbar. Apple-Store-Abos und Umsätze sind nicht in Supabase gespiegelt; echte App-Store-Preise und Abrechnungen bleiben in App Store Connect. Edge Functions prüfen Admin-Aktionen serverseitig anhand `app_metadata.role == "admin"`; der Service-Role-Key bleibt ausschließlich in der Supabase-Laufzeit. Der Publishable Key ist für öffentliche Clients vorgesehen und wird in den App-/Website-Build eingebunden.

Für Kennzahlen und Pro-Angebotstexte muss die Migration `20261012020000_add_app_analytics_and_pro_offer.sql`, für App-Rechnungen `20261013000000_add_invoice_management.sql`, für Kundengruppen und private Verkaufsbelege `20261013170000_add_admin_workspace.sql` sowie für interne Adminnotizen `20261013183000_add_admin_private_notes.sql` angewendet werden. `admin-console` und `user-portal` müssen deployed sein. Bei Supabase-Function-Aufrufen muss die CORS-Allow-Headers-Liste auch `x-supabase-api-version` erlauben.

### Einmalige Einrichtung

1. In Supabase unter **Project Settings > API Keys** den Projekt-URL-Wert und den **Publishable Key** kopieren. Keine `service_role`- oder Secret-Keys in die App, Website oder ein Git-Repository eintragen.
2. `Config/Supabase.xcconfig` und `website/supabase-config.js` enthalten den öffentlichen Publishable Key und die Projekt-URL. Beide werden für App-Build und öffentliches Admin-Web verwendet. Darin niemals einen Secret-/Service-Role-Key eintragen.
3. Im Projektordner im Terminal `npx supabase login` und `npx supabase link --project-ref jxewtyipeymxbjbckrrl` ausführen. Dann `npx supabase db push` sowie `npx supabase functions deploy admin-console --no-verify-jwt`, `npx supabase functions deploy account-delete --no-verify-jwt` und `npx supabase functions deploy user-portal --no-verify-jwt`. Die Functions validieren den Bearer-Token selbst; Admin-Funktionen prüfen zusätzlich die serverseitige Admin-Rolle.
4. Supabase **Authentication > Providers**: E-Mail/Passwort aktivieren und E-Mail-Bestätigung einschalten. In **Authentication > Emails** die HTML-Vorlagen aus `supabase/templates/` in **Confirm signup**, **Invite user** und **Reset password** einsetzen. Die Bestätigungsvorlage enthält den OTP-Code `{{ .Token }}` für iOS und Web-App sowie einen Bestätigungslink; die OTP-Gültigkeit auf **300 Sekunden** setzen. Einladung und Passwort-Reset leiten zur Seite `set-password.html`. Für produktiven E-Mail-Versand SMTP konfigurieren.
5. In **Authentication > URL Configuration** die GitHub-Pages-Adresse `https://jamietrading9-design.github.io/wertweit/` sowie `https://jamietrading9-design.github.io/wertweit/set-password.html` als Redirect-URLs eintragen. SMTP/E-Mail-Versand für Einladungen einrichten.
6. Ein Admin-Konto anlegen und im **App Metadata** `{"role":"admin"}` setzen (nicht in User Metadata). Danach in `website/admin.html` anmelden. Nur Administratoren sollten weitere Admin-Einladungen erstellen.
7. `Kursklar.xcodeproj` öffnen und die iPhone-App neu bauen/installieren. Kontoregistrierung, Anmeldung und Wartungsstatus verwenden dasselbe Supabase-Projekt.

Im Adminbereich kann eine Einladung erneut gesendet werden: Bei einem unbestätigten Konto wird die Registrierungsbestätigung erneut versendet; bei einem bereits bestätigten Konto erhält der Nutzer stattdessen einen Link zum Setzen des Passworts. Beides benötigt funktionierenden SMTP-Versand und die erlaubte Redirect-URL.

### E-Mail-Versand einrichten

Für Bestätigungscodes und Einladungen verwendet Supabase SMTP. Der Adminbereich versendet zusätzlich Einzel-E-Mails an ausgewählte Konten sowie Rundmails ausschließlich an Nutzer, die **Produktneuigkeiten per E-Mail** selbst in der App eingeschaltet haben. Die Auswahl wird in `email_update_preferences` gespeichert; Nutzer können sie jederzeit im App-Menü wieder ausschalten. Rundmails enthalten einen Abmeldehinweis. An einzelne, ausgewählte Konten sollen nur erforderliche Konto- oder Servicenachrichten gehen.

Der Absender für Wertweit ist `wertweitoffiziell@gmail.com`. Für diesen konkreten Absender ist ein Google-Konto plus Google Apps Script der einfachste kostenlose Weg: Supabase Auth verschickt Bestätigungscodes automatisch über Gmail-SMTP; die Admin-Webseite und Support-Antworten senden über ein kleines Apps-Script, das als dieses Gmail-Konto läuft. Google veröffentlicht für Apps Script derzeit ein Limit von 100 E-Mail-Empfängern pro Tag bei kostenlosen Gmail-Konten; Limits können geändert werden. Für den Adminversand ist keine eigene Versanddomain erforderlich. Neue Support-Anfragen lösen außerdem automatisch eine E-Mail an `wertweitoffiziell@gmail.com` aus.

#### Automatische Bestätigungscodes und Einladungen

1. Melde dich beim Google-Konto `wertweitoffiziell@gmail.com` an und aktiviere die **Bestätigung in zwei Schritten**. Erstelle anschließend unter [Google App-Passwörter](https://myaccount.google.com/apppasswords) ein App-Passwort. Verwende dieses App-Passwort, nicht dein normales Gmail-Passwort.
2. Öffne Supabase **Authentication > SMTP Settings**, aktiviere Custom SMTP und trage ein: Host `smtp.gmail.com`, Port `465` (SSL), Benutzername `wertweitoffiziell@gmail.com`, Passwort das Google-App-Passwort, Absender-E-Mail `wertweitoffiziell@gmail.com`, Absendername `Wertweit`. Speichere es nur im Supabase-Dashboard; nicht in Xcode, Git oder der Website.
3. In Supabase **Authentication > Providers** E-Mail/Passwort und E-Mail-Bestätigung aktivieren. Die gestalteten Vorlagen `supabase/templates/confirmation.html`, `invite.html` und `recovery.html` in Supabase **Authentication > Emails** bei **Confirm signup**, **Invite user** und **Reset password** einsetzen. Hosted-Supabase übernimmt diese Vorlagen nicht automatisch aus dem Repository. Die Bestätigungsvorlage muss `{{ .Token }}` enthalten; stelle die OTP-Gültigkeit auf **300 Sekunden**. Supabase verschickt Codes, Registrierungsbestätigungen, Passwort-Resets und Admin-Einladungen dann automatisch. Das kostenlose Supabase-Test-SMTP kann nur an Projekt-Teamadressen senden und reicht nicht für echte Nutzer.

Falls Google kein App-Passwort für dieses Konto anbietet oder Gmail SMTP von Supabase nicht akzeptiert, hält das Konto diese Verbindung nicht frei; dann ist ein SMTP-Anbieter mit kostenloser Stufe nötig, aber normalerweise mit eigener verifizierter Domain.

#### Admin-E-Mails und Support-Antworten

1. In `scripts/wertweit-email-sender.gs` den Code in ein neues [Google Apps Script](https://script.google.com/) kopieren, während du als `wertweitoffiziell@gmail.com` angemeldet bist.
2. In Apps Script **Projekteinstellungen > Skripteigenschaften** eine zufällige, lange Zeichenfolge als `WERTWEIT_MAIL_SECRET` speichern. Nicht in den Code schreiben und nicht weitergeben.
3. **Bereitstellen > Neue Bereitstellung > Web-App** wählen. **Ausführen als**: ich (`wertweitoffiziell@gmail.com`); **Zugriff**: alle. Bereitstellen und die Web-App-URL kopieren. Die URL ist öffentlich erreichbar, aber jeder Versand benötigt das geheime Token; teile URL und Token nicht öffentlich.
4. In Supabase **Edge Functions > Secrets** zwei Secrets anlegen: `GOOGLE_APPS_SCRIPT_URL` erhält die Web-App-URL und `GOOGLE_APPS_SCRIPT_TOKEN` exakt dasselbe Geheimnis wie `WERTWEIT_MAIL_SECRET`. Diese Werte nur in Supabase/Apps Script eintragen, nicht in der App oder Website.

5. Die Migrationen und die Functions ausrollen:

   ```sh
   npx supabase db push
   npx supabase functions deploy admin-console --no-verify-jwt
   npx supabase functions deploy user-portal --no-verify-jwt
   ```

   `db push` spielt auch die Migrationen für E-Mail-Einwilligungen, Ticket-Übernahme und App-Benachrichtigungen ein. Admin-Aktionen prüfen weiterhin die Admin-Rolle serverseitig.
6. In der Admin-Webseite Nutzer auf der Seite „Datenbank“ markieren, Betreff und Text eintragen und den Versand bestätigen. Der lokale Textassistent erstellt bearbeitbare E-Mail-Entwürfe aus festen Vorlagen für Service, Support, Rechnungen und Produktneuigkeiten. Er verwendet keine KI und keinen API-Schlüssel; Stichpunkte verbleiben im Browser. Werbe- und Produktmails werden serverseitig auf Nutzer mit aktivierter Einwilligung in der App beschränkt. Einzelne ausgewählte Konten erfordern eine Bestätigung, dass es sich um eine notwendige Konto- oder Servicenachricht ohne Werbung handelt. Pro Versand sind höchstens 99 Nutzer vorgesehen, weil Gmail auch eine Kopie an das eigene Postfach sendet; das kostenlose Gmail-Limit liegt derzeit bei 100 Empfängern pro Tag insgesamt. Neue Support-Tickets senden automatisch eine Mail an `wertweitoffiziell@gmail.com`; darin stehen Absenderkontakt, Dringlichkeit, Kategorie, Betreff und Nachricht. Die Support-Mail setzt die E-Mail-Adresse des Nutzers als Antwortadresse, sodass du direkt aus Gmail antworten kannst. Eine Antwort aus dem Adminbereich wird zusätzlich in der App gespeichert und per E-Mail an den Nutzer geschickt. Versandfehler erscheinen gesondert im Adminbereich.

Test zuerst mit deiner eigenen E-Mail. Admin-, Wartungs- und Support-E-Mails erhalten ein einheitliches Wertweit-Layout mit Logo, Markenfarben, gut lesbarer Überschrift, strukturierten Supportdetails und Link zur Web-App; der eingegebene Nachrichtentext wird sicher als Text dargestellt und nicht als HTML ausgeführt. Apps Script prüft sein tägliches Gmail-Kontingent vor Rundmails und meldet teilweise fehlgeschlagene Zustellungen. Wenn du den Apps-Script-Code änderst, musst du eine neue Web-App-Version bereitstellen.

Supabase SMTP Dokumentation: https://supabase.com/docs/guides/auth/auth-smtp. Google App-Passwörter: https://support.google.com/accounts/answer/185833. Apps-Script-E-Mail-Limits: https://developers.google.com/apps-script/guides/services/quotas.

Das im Supabase-Dashboard angebotene MCP-Kommando `claude mcp add ...` ist nur für Claude Code und in deinem Screenshot schreibgeschützt. Es ist nicht die App-Verbindung. Dafür in Supabase die Client-Library-Integration wählen; für Kontolisten und privilegierte Admin-Aktionen werden Edge Functions verwendet. Keine direkte Datenbank-Connection-String-Verbindung aus iPhone oder Website.

## App-Benachrichtigungen

Admin-E-Mails erzeugen zusätzlich einen Eintrag in der Benachrichtigungs-Inbox der betroffenen Konten. Für echte Mitteilungen, wenn die iPhone-App geschlossen ist, braucht jedes Gerät eine Push-Berechtigung und der Server einen Apple-APNs-Schlüssel:

1. Eine aktive Mitgliedschaft im kostenpflichtigen Apple Developer Program verwenden. Ein kostenloses Personal-Team unterstützt die Push Notifications Capability nicht. Anschließend Push Notifications für die Bundle-ID `de.wertweit.app` aktivieren und einen APNs Auth Key erstellen. Key-ID, Team-ID und die `.p8`-Datei sicher aufbewahren.
2. APNs-Key ausschließlich als Supabase-Function-Secret setzen, nicht in Xcode, Git oder die Website. Dafür lokal eine nicht eingecheckte Env-Datei mit `APPLE_TEAM_ID`, `APPLE_APNS_KEY_ID`, `APPLE_APNS_PRIVATE_KEY`, `APPLE_APNS_TOPIC=de.wertweit.app` und `APPLE_APNS_ENVIRONMENT` anlegen. Für Debug-Builds ist die APNs-Umgebung `sandbox`, für App-Store-Builds `production`.
3. Secrets setzen: `npx supabase secrets set --project-ref jxewtyipeymxbjbckrrl --env-file <private-env-datei>`.
4. Die App mit aktivierter Push-Entitlement signieren und verteilen. Nutzer müssen Push im App-Menü erlauben. Erst danach meldet das Gerät sein APNs-Token bei Supabase an.

Bis Apple-Key, Push-Capability und ein entsprechend signierter App-Build eingerichtet sind, werden Benachrichtigungen in der App-Inbox gespeichert, aber nicht als echte Hintergrund-Push zugestellt. Der Adminbereich zeigt den Push-Status nach einem E-Mail-Versand an.

## Web-App

Die responsive, installierbare Browser-App liegt unter `website/waehrungsrechner-app-web/` und wird zusammen mit der übrigen Website unter `/waehrungsrechner-app-web/` veröffentlicht. Anmeldung und Passwort nutzen dasselbe Supabase-Konto wie die iOS-App; beide Clients bestätigen neue Konten mit einem E-Mail-Code. Dafür muss die Supabase-Vorlage `{{ .Token }}` enthalten und ein funktionierender SMTP-Versand eingerichtet sein. Passwort-Reset und Einladungen öffnen die gemeinsame Seite `/set-password.html`. Der separate Gmail-Versand der Admin-Seite richtet Supabase Auth SMTP nicht ein. Die Web-App bietet Rechner, Reise, Wechselwerkzeuge, Kursübersicht, Inbox, E-Mail-Einstellungen und Support. Web-Käufe und die Synchronisierung von Apple-App-Store-Abos sind noch nicht eingerichtet; im Web wird nur ein vom Server gewährter Pro-Zugang erkannt.

Neue Support-Tickets werden serverseitig mit lokalen, regelbasierten Schlüsselworten einer Kategorie und einer Dringlichkeit zugeordnet; es wird dafür kein KI-Anbieter oder externer API-Aufruf verwendet. Rot kennzeichnet Sicherheits-, Datenverlust- und vergleichbare dringende Meldungen, Gelb Probleme mit App, Konto oder Zahlung und Grün allgemeine Fragen oder Wünsche. Die Einstufung steht im Admin-Postfach und im Betreff der Support-E-Mail. Beim Ein- und Ausschalten des Wartungsmodus wird eine Service-E-Mail an das Admin-Postfach und an bestätigte Konten mit aktiver E-Mail-Einwilligung gesendet. Wegen des kostenlosen Gmail-Kontingents werden höchstens 99 Nutzer pro Wartungswechsel per E-Mail erreicht; die Admin-Seite weist auf ausgelassene Empfänger hin.

## GitHub

Das Projekt kann als öffentliches Repository mit GitHub Pages veröffentlicht werden. Der Workflow `.github/workflows/deploy-pages.yml` veröffentlicht ausschließlich `website/`. Die Admin-Seite benötigt weiterhin Supabase-Login und serverseitige Admin-Rollen. GitHub speichert den Quellcode und hostet die statische Website; Migrationen und Functions werden separat mit der Supabase CLI ausgerollt. Client-Publishable-Keys sind öffentlich und kein Ersatz für RLS oder serverseitige Rollenprüfungen.

Impressum und Datenschutzhinweis sind in der App enthalten. Vor einer Veröffentlichung müssen die Angaben zu Supabase, Kontodaten, Hostingregion, Löschung und tatsächlichen Datenverarbeitungspraktiken rechtlich und sachlich geprüft sowie in die öffentlich erreichbare Datenschutzrichtlinien-URL übernommen werden.