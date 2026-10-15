# ShopKeep (Flutter: Android + PWA)
1. `flutter create . --platforms=android,web` (adds platform folders), then `flutter pub get`
2. `flutter run -d chrome`  |  `flutter build web --release --pwa-strategy=offline-first`
3. Set `apiBase` in lib/data.dart. Backend needs: POST /sync, POST /payments/momo, GET /payments/momo/:ref, notify handler (SMS + WhatsApp).

## Android note for receipts
In android/app/src/main/AndroidManifest.xml add inside <manifest>:
`<queries><intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent><intent><action android:name="android.intent.action.VIEW"/><data android:scheme="sms"/></intent></queries>`

## Printing, scanning, lockout
Android manifest (inside <manifest>): camera for scanning, Bluetooth for printing:
`<uses-permission android:name="android.permission.CAMERA"/>`
`<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>`
`<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>`
Printing: 58mm Bluetooth ESC/POS printers, paired first in phone settings. Web build shows a stub.
Scanning: camera scanning works in the Android app. USB / Bluetooth scanners work everywhere (they type the code and press Enter in the Sell search box). Camera scanning on web needs extra setup, see the mobile_scanner docs.
PIN lockout: 5 wrong tries lock a phone number for 15 minutes on the device, and on the server too.
