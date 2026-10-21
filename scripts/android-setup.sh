#!/usr/bin/env bash
# Wordt door de bouwstraat aangeroepen na "npx cap add android".
# Rechten, versienummer en de app-naam per telefoontaal.
set -euo pipefail
RUN="${RUN_NUMBER:-1}"
M=android/app/src/main/AndroidManifest.xml
grep -q ACCESS_FINE_LOCATION "$M" || perl -0pi -e 's#</manifest>#    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n</manifest>#' "$M"
perl -pi -e "s/versionCode \\d+/versionCode ${RUN}/; s/versionName \"[^\"]*\"/versionName \"0.1.${RUN}\"/" android/app/build.gradle

R=android/app/src/main/res
name() { # map naam
  mkdir -p "$R/$1"
  cat > "$R/$1/strings.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">$2</string>
    <string name="title_activity_main">$2</string>
</resources>
XML
}
# Standaard (alle overige talen): Engels; capacitor.config.json zet values/strings.xml al op de Engelse naam.
name values-nl "Zala - Boodschappen App"
name values-de "Zala - Einkaufs-App"
name values-hu "Zala - Bevásárló App"
name values-en "Zala - Shopping App"
echo "Android-instellingen toegepast (versie 0.1.${RUN})."
