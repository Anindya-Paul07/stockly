# Stockly — offline Flutter inventory

Functional first version for Android and iOS. All inventory data resides in a local SQLite database, with no server, login, API or runtime internet dependency. The UI is plain Material 3 so it can be redesigned without changing database or reporting code.

## Run

Install Flutter stable (3.27 or newer), Android Studio / Android SDK and Java 17. Connect an Android phone with USB debugging enabled. From this folder:

```bash
flutter create --platforms=android,ios --org com.stockly --project-name stockly .
flutter pub get
flutter analyze
flutter test
flutter run
```

The first command generates the standard native runners; they are not included in this source bundle. If Flutter generates a default `test/widget_test.dart`, delete that generated counter-app test before running the tests. Keep the supplied inventory_test.dart. Flutter will need internet for initial setup and dependencies. The installed app works offline. iOS building requires macOS and Xcode; use an iOS deployment target of at least 12.

To build an Android release APK after verification:

```bash
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`. Configure your own application ID and release signing before publishing.

## Try this workflow

1. Add Rice, SKU R001, unit bags, minimum 2.
2. Record stock in: 10, note Opening stock.
3. Record stock out: 3. Current quantity should be 7.
4. Try stock out: 8. It must fail and leave quantity at 7.
5. Close and reopen the app. Quantity and history should remain.
6. Generate Excel under Reports. Save a copy through the phone share sheet; inspect Inventory, Movements and Summary in Excel.
7. Unload the remaining 7. Archive the item. Its history should remain in the report.
8. Repeat in airplane mode.

## Implementation

- `lib/data/inventory_store.dart`: versioned SQLite schema, parameterized queries, transactions, stock checks, archive and consistent report snapshots.
- `lib/services/excel_report.dart`: actual .xlsx generation, typed text and numeric cells, inventory and complete movement history.
- `lib/ui/home_screen.dart`: inventory, forms, history, export and share sheet.
- `lib/main.dart`: application startup and database error retry.
- `test/inventory_test.dart`: SQLite integration tests, concurrent withdrawals, persistence and workbook round-trip tests.

Balances derive from signed movements: loading is positive; unloading is negative. A withdrawal and its stock check occur in one transaction. A failed withdrawal does not add history. New items start at zero; opening stock is a normal stock-in record. SKU uniqueness also covers archived items. Item units are fixed in the editing interface after creation. Details edits affect displayed names in historical reports. Movement quantities and timestamps cannot be edited; correct mistakes with an opposite movement and note. Timestamps are stored in UTC and shown in local time in the app.

## Scope and limits

This version uses whole-number quantities (pcs, boxes, bags). Fractional kg/litre quantities, pricing/valuation, barcode scanning, date-range reports, backup/restore, report browser, and multiple warehouses are not implemented. Different units are not added into one meaningless overall total.

Excel reports are saved to the app documents/reports folder before opening the system share sheet. Use the share sheet to keep them outside the app. Excel is an export, not a restorable database backup. Uninstalling the app or clearing app data may remove the inventory and local reports. OS-level device backup settings may also affect app data; there is no app-managed cloud sync.

## Verification status

Source and SQL integrity checks were completed in the authoring environment. Flutter and Dart are not installed there, so dependencies could not be resolved, Dart analysis and the supplied Flutter tests could not be run, and no APK or phone validation is claimed. Run the commands and manual workflow above on your Flutter machine before using real inventory.
