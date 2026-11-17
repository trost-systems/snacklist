# Runde DN: den Namen beim Einrichten erfragen
<!-- pick: DN3 -->
<!-- runner-up: DN4 -->

## Empfehlung

**Wahl: DN3 Bestätigen nach der Anmeldung.** Jeder Weg zu einer gemeinsamen Liste führt über die Anmeldung, für alle, die einen Haushalt anlegen, und für alle, die per Einladung beitreten. Direkt danach fragt ein Bildschirm, einmal. Mit einem Namen von Google oder Apple zeigt er ihn mit „Ja, das bin ich“: ein Tipp, nichts zu tippen. Ohne Namen (Anmeldung per E-Mail oder Apple ohne geteilten Namen) ist das Feld leer und Pflicht. Das ist Peters „Wie sollen wir dich nennen?“ beim Einrichten, für alle, und niemand landet als „lea.brandt87“ auf der Liste. Es kostet alle Neuen einen Bildschirm und einen Tipp, auch wer allein einkauft.

**Zweite Wahl: DN4 Gefragt, wenn es zählt.** Die günstigste Option: 0 Tipps und 0 Bildschirme, wenn Google oder Apple einen Namen mitliefert, und das Blatt sagt, warum es fragt („Dein·e Partner·in sieht, von wem die Einladung kommt“). Aber „Jetzt nicht“ lässt den E-Mail-Teil in der Mitgliederliste. Die Frage kommt außerdem mitten im Teilen, und wer allein startet und Wochen später einlädt, trifft sie erst dann. Sie ist die bessere Wahl, wenn ein Bildschirm weniger beim Einrichten mehr zählt als ein Name für alle.

Nicht gewählt:
- **DN1 Ein eigener Schritt** fragt vor dem Konto, wenn der Name von Google oder Apple noch nicht bekannt ist. Also tippen alle, auch Google-Nutzer, und Eingeladene bekommen nach der Anmeldung eine zweite Fassung des Bildschirms.
- **DN2 Ein Feld beim Haushaltsnamen** braucht keinen Bildschirm, aber ein freiwilliges zweites Feld. Bleibt es leer (der Weg „übersprungen“), bleibt das heutige „lea.brandt87“, und Eingeladene brauchen das Feld noch einmal beim Beitritt.
- **DN5 Die erste Frage, überspringbar** wirkt persönlich („Lea, mit wem kaufst du ein?“). Sie fragt aber, bevor Google oder Apple etwas vorausfüllen können, und Überspringen lässt den E-Mail-Teil.

## Gemessen

Das Prüfskript geht jede Option mit echten Klicks durch, von „Mit wem kaufst du ein?“ (oder der Beitrittsseite) bis zur Liste. Es zählt jeden Tipp, auch den Tipp in ein Feld, das den Fokus nicht von selbst bekommt. Die Tabelle zeigt den Unterschied zu heute für dieselbe Person. Ein Google- oder Apple-Blatt zählt einen Tipp, Tippen auf der Tastatur zählt nicht. „Übersprungen“ ist der Weg, der nie einen Namen eingibt, wo man ihn weglassen kann. Überlauf heißt abgeschnittener, über das Telefon ragender oder überlappender Text oder ein Ziel unter 44 px. Geprüft wurde auf jedem Bildschirm jedes Durchgangs und jedes Bildes, auf Englisch und Deutsch, bei 100 %, 200 % (das Größte bei Android und die Zahl der WCAG) und 310 % (die größte Bedienungshilfen-Größe bei iOS; die App hat keine globale Grenze), für fünf Personen (E-Mail, Google, Apple ohne Namen, ein Name mit 49 Zeichen, ein Name mit Emoji).

<!-- table:start -->
| Option | Bildschirme mehr, anlegen (E-Mail / Google) | Tipps mehr, anlegen (E-Mail / Google / Apple verborgen) | Tipps mehr, beitreten (E-Mail / Google) | Getippt, anlegen (E-Mail / Google / Apple verborgen) | Peter sieht (E-Mail) | Übersprungen (anlegen / beitreten) | Überlauf bei 100 % und 200 % | Überlauf bei 310 % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| today | 0 / 0 | 0 / 0 / 0 | 0 / 0 | nein / nein / nein | lea.brandt87 | lea.brandt87 / lea.brandt87 | keiner | keiner |
| DN1 | +1 / +1 | +1 / +1 / +1 | +1 / +1 | ja / ja / ja | Lea | Pflicht / Pflicht | keiner | keiner |
| DN2 | 0 / 0 | +1 / +1 / +1 | +1 / 0 | ja / ja / ja | Lea | lea.brandt87 / lea.brandt87 | keiner | keiner |
| DN3 | +1 / +1 | +1 / +1 / +1 | +1 / +1 | ja / nein / ja | Lea | Pflicht / Pflicht | keiner | keiner |
| DN4 | +1 / 0 | +1 / 0 / +1 | +1 / 0 | ja / nein / ja | Lea | lea.brandt87 / lea.brandt87 | keiner | keiner |
| DN5 | +1 / +1 | +1 / +1 / +1 | +1 / +1 | ja / ja / ja | Lea | lea.brandt87 / lea.brandt87 | keiner | keiner |
<!-- table:end -->

So liest man die Tabelle. Jede Option kostet E-Mail-Nutzer einen Tipp. Unterschiede gibt es bei Google- und Apple-Nutzern und darin, was übrig bleibt, wenn jemand überspringt. Nur DN1 und DN3 lassen sich nicht überspringen, und von beiden braucht nur DN3 kein Tippen von Google-Nutzern. Bei 310 % läuft in keiner Option ein Bildschirm über. Lange Wörter brechen, wie Flutter sie bricht, und die Schritte scrollen.

## Offene Fragen

- **DN-Q1** Pflicht oder freiwillig? Vorschlag: Pflicht. „Weiter“ in DN3 bleibt aus, bis das Feld 1 Zeichen hat, und es gibt kein Überspringen.
- **DN-Q2** Wie lang? Vorschlag: 1 bis 80 Zeichen (die Grenze der Datenbank, wie beim Haushaltsnamen), mit Flutters Zähler „n/80“ unter dem Feld wie beim Haushaltsnamen (Screenreader hören „noch 67 Zeichen“).
- **DN-Q3** Vorname oder voller Name? Vorschlag: freier Text mit der Beschriftung „Dein Name“, vorausgefüllt mit dem vollen Namen von Google oder Apple. Die Beitrittsseite zeigt weiter nur das erste Wort, wie heute.
- **DN-Q4** Überschreibt ein späterer Name von Google oder Apple einen selbst gesetzten? Vorschlag: nein, und der heutige Code garantiert das nicht. `handle_user_metadata_update` ersetzt den Profilnamen, solange er dem aus den alten Metadaten abgeleiteten Namen gleicht. Das ist der E-Mail-Teil, aber auch der alte Name von Google oder Apple. Ein „Ja, das bin ich“, direkt in `profiles` geschrieben, würde also von Apples erster Anmeldung oder einer verknüpften Google-Identität überschrieben. Vorschlag: Jedes Schreiben des Namens (Bestätigen oder Feld in DN3, das Blatt in DE1) geht über `updateUser(data: {display_name})`, das `default_display_name` an erste Stelle setzt. Der Trigger übernimmt ihn dann in `profiles` und hält ihn gegen spätere Namen der Anbieter. Geprüft in einem Wegwerf-Postgres mit den beiden echten Funktionen. Direkt in `profiles` geschrieben, wurde ein bestätigtes „Lea Brandt“ nach einer Metadaten-Änderung zu „Lea M. Brandt“. Als `display_name` in den Metadaten blieb es „Lea Brandt“, und eine spätere Änderung zu „Lea“ ging durch. Das `source: chosen` des Prototyps ist dieses Ziel, nicht das heutige Verhalten.
- **DN-Q5** Bestehende Nutzer mit E-Mail-Teil als Namen, wie das Haushaltsmitglied, das gefragt hat? Vorschlag: Sie bekommen den Bildschirm von DN3 einmal beim nächsten App-Start, nur für sie mit „Jetzt nicht“, danach die Zeile im Konto (DE1).
- **DN-Q6** Wo genau? Vorschlag: Wer anlegt, sieht ihn nach dem Konto und bevor der Haushalt eingerichtet wird, als eigener gezählter Schritt („Schritt 7 von 8“, damit sich der Balken bewegt). Wer beitritt, sieht ihn vor dem Beitritt, damit eine Beitrittsanfrage („Beitritte bestätigen“) schon den Namen trägt.
- **DN-Q7** Welche Zeichen? Vorschlag: alles Druckbare, auch Emoji. Leerzeichen trimmen und zusammenfassen, kein Wortfilter. Der Name mit 49 Zeichen und „Lea 🌻“ passen bei 200 % in jeder Option.
- **DN-Q8** Analytics? Vorschlag: kein neues Ereignis und nie der Name. Falls gewünscht, `display_name_set` nur mit `prefilled: true|false`, eingetragen in die Allow-List.
