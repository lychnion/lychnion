import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Lychnion'**
  String get appName;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @beforeYouStart.
  ///
  /// In en, this message translates to:
  /// **'Before you start'**
  String get beforeYouStart;

  /// No description provided for @iUnderstand.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get iUnderstand;

  /// No description provided for @downloadsErrorOffline.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get downloadsErrorOffline;

  /// No description provided for @downloadsErrorWifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Connect to Wi-Fi (mobile data is off in the setting above).'**
  String get downloadsErrorWifiOnly;

  /// No description provided for @downloadsErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'The connection dropped. \"Resume\" continues where it stopped.'**
  String get downloadsErrorNetwork;

  /// No description provided for @downloadsErrorChecksum.
  ///
  /// In en, this message translates to:
  /// **'The file was damaged and has been removed. Please download again.'**
  String get downloadsErrorChecksum;

  /// No description provided for @downloadsErrorChecksumLocal.
  ///
  /// In en, this message translates to:
  /// **'This file does not match the catalog. Delete it and download again.'**
  String get downloadsErrorChecksumLocal;

  /// No description provided for @downloadsErrorBusy.
  ///
  /// In en, this message translates to:
  /// **'Already downloading in another window.'**
  String get downloadsErrorBusy;

  /// No description provided for @downloadsErrorDiskFull.
  ///
  /// In en, this message translates to:
  /// **'Not enough free space.'**
  String get downloadsErrorDiskFull;

  /// No description provided for @downloadsErrorDisk.
  ///
  /// In en, this message translates to:
  /// **'Could not save the file.'**
  String get downloadsErrorDisk;

  /// No description provided for @downloadsErrorSignature.
  ///
  /// In en, this message translates to:
  /// **'This download is not signed by Lychnion, so it was not installed.'**
  String get downloadsErrorSignature;

  /// No description provided for @downloadsErrorOlder.
  ///
  /// In en, this message translates to:
  /// **'This is an older version than the one installed, so it was not installed.'**
  String get downloadsErrorOlder;

  /// No description provided for @downloadsErrorTaken.
  ///
  /// In en, this message translates to:
  /// **'This ID or one of its files is already installed from another publisher, so it was not installed.'**
  String get downloadsErrorTaken;

  /// No description provided for @downloadsLargeWarning.
  ///
  /// In en, this message translates to:
  /// **'This downloads {size}. Please use Wi-Fi. You need at least {size} of free space. If it stops, you can resume where it left off.'**
  String downloadsLargeWarning(String size);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @downloadsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadsDownload;

  /// No description provided for @downloadsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get downloadsDeleteTitle;

  /// No description provided for @downloadsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Removes {title} ({size}) from this device. You cannot get it back while offline.'**
  String downloadsDeleteBody(String title, String size);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @downloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadsTitle;

  /// No description provided for @downloadsWifiOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Models and maps can be several GB. \"Ask first\" asks before each download over mobile data.'**
  String get downloadsWifiOnlyHint;

  /// No description provided for @downloadsFooter.
  ///
  /// In en, this message translates to:
  /// **'Everything downloaded works offline. Files are checked (SHA-256) before the app uses them.'**
  String get downloadsFooter;

  /// No description provided for @downloadsKindModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get downloadsKindModels;

  /// No description provided for @downloadsKindPackages.
  ///
  /// In en, this message translates to:
  /// **'Knowledge packages'**
  String get downloadsKindPackages;

  /// No description provided for @downloadsKindMaps.
  ///
  /// In en, this message translates to:
  /// **'Map areas'**
  String get downloadsKindMaps;

  /// No description provided for @downloadsTooLargeForPhone.
  ///
  /// In en, this message translates to:
  /// **'Too large for most phones.'**
  String get downloadsTooLargeForPhone;

  /// No description provided for @downloadsNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get downloadsNotDownloaded;

  /// No description provided for @downloadsNoSource.
  ///
  /// In en, this message translates to:
  /// **'No download source yet (uses the copy in the app)'**
  String get downloadsNoSource;

  /// No description provided for @downloadsPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused: {done} of {total}'**
  String downloadsPaused(String done, String total);

  /// No description provided for @downloadsUnverified.
  ///
  /// In en, this message translates to:
  /// **'File present (not checked yet)'**
  String get downloadsUnverified;

  /// No description provided for @downloadsInstalled.
  ///
  /// In en, this message translates to:
  /// **'Downloaded and checked'**
  String get downloadsInstalled;

  /// No description provided for @downloadsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available (on device: {version})'**
  String downloadsUpdateAvailable(String version);

  /// No description provided for @downloadsStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get downloadsStop;

  /// No description provided for @downloadsResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get downloadsResume;

  /// No description provided for @downloadsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get downloadsUpdate;

  /// No description provided for @downloadsCheckFile.
  ///
  /// In en, this message translates to:
  /// **'Check file'**
  String get downloadsCheckFile;

  /// No description provided for @downloadsInUse.
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get downloadsInUse;

  /// No description provided for @downloadsUseModel.
  ///
  /// In en, this message translates to:
  /// **'Use this model'**
  String get downloadsUseModel;

  /// No description provided for @downloadsCheckingPart.
  ///
  /// In en, this message translates to:
  /// **'Checking the part already downloaded…'**
  String get downloadsCheckingPart;

  /// No description provided for @downloadsVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking the checksum… {percent}%'**
  String downloadsVerifying(String percent);

  /// No description provided for @downloadsEtaOneMinute.
  ///
  /// In en, this message translates to:
  /// **'about 1 min left'**
  String get downloadsEtaOneMinute;

  /// No description provided for @downloadsEtaMinutes.
  ///
  /// In en, this message translates to:
  /// **'about {minutes} min left'**
  String downloadsEtaMinutes(String minutes);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String minutesAgo(String minutes);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours} h ago'**
  String hoursAgo(String hours);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String daysAgo(String days);

  /// No description provided for @factSourceOfficialUnverified.
  ///
  /// In en, this message translates to:
  /// **'says official, not verified'**
  String get factSourceOfficialUnverified;

  /// No description provided for @factSourceSensorUnverified.
  ///
  /// In en, this message translates to:
  /// **'says sensor, not verified'**
  String get factSourceSensorUnverified;

  /// No description provided for @factSourceOfficial.
  ///
  /// In en, this message translates to:
  /// **'official'**
  String get factSourceOfficial;

  /// No description provided for @factSourceSensor.
  ///
  /// In en, this message translates to:
  /// **'sensor'**
  String get factSourceSensor;

  /// No description provided for @factSourceCitizen.
  ///
  /// In en, this message translates to:
  /// **'resident report, unconfirmed'**
  String get factSourceCitizen;

  /// No description provided for @shelterStatus.
  ///
  /// In en, this message translates to:
  /// **'{status, select, open{open} crowded{crowded} full{full} closed{closed} other{{status}}}'**
  String shelterStatus(String status);

  /// No description provided for @factRoadBlocked.
  ///
  /// In en, this message translates to:
  /// **'road blocked'**
  String get factRoadBlocked;

  /// No description provided for @factWater.
  ///
  /// In en, this message translates to:
  /// **'water: {value}'**
  String factWater(String value);

  /// No description provided for @factUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'unconfirmed'**
  String get factUnconfirmed;

  /// No description provided for @factsBoxTitle.
  ///
  /// In en, this message translates to:
  /// **'Current information · not from the AI'**
  String get factsBoxTitle;

  /// No description provided for @factsBoxRoadBlocked.
  ///
  /// In en, this message translates to:
  /// **'Road blocked'**
  String get factsBoxRoadBlocked;

  /// No description provided for @factsBoxWater.
  ///
  /// In en, this message translates to:
  /// **'Water: {value}'**
  String factsBoxWater(String value);

  /// No description provided for @factsBoxAddWarning.
  ///
  /// In en, this message translates to:
  /// **'Add warning'**
  String get factsBoxAddWarning;

  /// No description provided for @factFormWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning (e.g. 津波警報)'**
  String get factFormWarning;

  /// No description provided for @factFormNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get factFormNote;

  /// No description provided for @factFormValidFor.
  ///
  /// In en, this message translates to:
  /// **'Valid for'**
  String get factFormValidFor;

  /// No description provided for @factFormHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String factFormHours(String hours);

  /// No description provided for @factFormOfficial.
  ///
  /// In en, this message translates to:
  /// **'Official (staff, city)'**
  String get factFormOfficial;

  /// No description provided for @factFormResident.
  ///
  /// In en, this message translates to:
  /// **'Resident report'**
  String get factFormResident;

  /// No description provided for @factFormClear.
  ///
  /// In en, this message translates to:
  /// **'No longer true'**
  String get factFormClear;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @hazardName.
  ///
  /// In en, this message translates to:
  /// **'{hazard, select, tsunami{Tsunami} earthquake{Earthquake} flood{Flood} landslide{Landslide} stormSurge{Storm surge} fire{Large fire} inlandFlood{Inland flooding} volcano{Volcano} other{{hazard}}}'**
  String hazardName(String hazard);

  /// No description provided for @hazardInSentence.
  ///
  /// In en, this message translates to:
  /// **'{hazard, select, tsunami{tsunami} earthquake{earthquake} flood{flood} landslide{landslide} stormSurge{storm surge} fire{large fire} inlandFlood{inland flooding} volcano{volcano} other{{hazard}}}'**
  String hazardInSentence(String hazard);

  /// No description provided for @compassPoint.
  ///
  /// In en, this message translates to:
  /// **'{point, select, n{N} ne{NE} e{E} se{SE} s{S} sw{SW} w{W} nw{NW} other{{point}}}'**
  String compassPoint(String point);

  /// No description provided for @siteHeight.
  ///
  /// In en, this message translates to:
  /// **'{height} m above sea level'**
  String siteHeight(String height);

  /// No description provided for @siteFlooding.
  ///
  /// In en, this message translates to:
  /// **'expected flooding {depth}'**
  String siteFlooding(String depth);

  /// No description provided for @siteDip.
  ///
  /// In en, this message translates to:
  /// **'dips to {height} m on the way'**
  String siteDip(String height);

  /// No description provided for @siteWalk.
  ///
  /// In en, this message translates to:
  /// **'{distance} walk · about {minutes} min'**
  String siteWalk(String distance, String minutes);

  /// No description provided for @siteStraight.
  ///
  /// In en, this message translates to:
  /// **'{distance} {direction} · straight line'**
  String siteStraight(String distance, String direction);

  /// No description provided for @depthOrMore.
  ///
  /// In en, this message translates to:
  /// **'{lo} m or more'**
  String depthOrMore(String lo);

  /// No description provided for @depthUnder.
  ///
  /// In en, this message translates to:
  /// **'under {hi} m'**
  String depthUnder(String hi);

  /// No description provided for @depthRange.
  ///
  /// In en, this message translates to:
  /// **'{lo}–{hi} m'**
  String depthRange(String lo, String hi);

  /// No description provided for @depthLegendUnder.
  ///
  /// In en, this message translates to:
  /// **'under 0.3 m'**
  String get depthLegendUnder;

  /// No description provided for @depthLegendFrom.
  ///
  /// In en, this message translates to:
  /// **'from {lo} m'**
  String depthLegendFrom(String lo);

  /// No description provided for @mapWarningFor.
  ///
  /// In en, this message translates to:
  /// **'Warning for {city}'**
  String mapWarningFor(String city);

  /// No description provided for @mapRoadBlockedHere.
  ///
  /// In en, this message translates to:
  /// **'Road blocked here'**
  String get mapRoadBlockedHere;

  /// No description provided for @mapWaterHere.
  ///
  /// In en, this message translates to:
  /// **'Water handed out here'**
  String get mapWaterHere;

  /// No description provided for @mapRoadBlocked.
  ///
  /// In en, this message translates to:
  /// **'Road blocked'**
  String get mapRoadBlocked;

  /// No description provided for @mapWaterPoint.
  ///
  /// In en, this message translates to:
  /// **'Water point'**
  String get mapWaterPoint;

  /// No description provided for @mapWaterTruck.
  ///
  /// In en, this message translates to:
  /// **'water truck'**
  String get mapWaterTruck;

  /// No description provided for @mapWaterStation.
  ///
  /// In en, this message translates to:
  /// **'water station'**
  String get mapWaterStation;

  /// No description provided for @mapWhichHazard.
  ///
  /// In en, this message translates to:
  /// **'Which hazard?'**
  String get mapWhichHazard;

  /// No description provided for @mapTestLocation.
  ///
  /// In en, this message translates to:
  /// **'Test location'**
  String get mapTestLocation;

  /// No description provided for @mapLocationAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Location ±{meters} m'**
  String mapLocationAccuracy(String meters);

  /// No description provided for @mapNoLocationPermission.
  ///
  /// In en, this message translates to:
  /// **'No location permission'**
  String get mapNoLocationPermission;

  /// No description provided for @mapNoLocation.
  ///
  /// In en, this message translates to:
  /// **'Location not available'**
  String get mapNoLocation;

  /// No description provided for @mapHazard.
  ///
  /// In en, this message translates to:
  /// **'Hazard'**
  String get mapHazard;

  /// No description provided for @mapChooseHazard.
  ///
  /// In en, this message translates to:
  /// **'Choose the hazard'**
  String get mapChooseHazard;

  /// No description provided for @mapAttributionSites.
  ///
  /// In en, this message translates to:
  /// **'Evacuation sites: GSI Japan'**
  String get mapAttributionSites;

  /// No description provided for @mapAttributionHeights.
  ///
  /// In en, this message translates to:
  /// **'Heights: GSI elevation tiles'**
  String get mapAttributionHeights;

  /// No description provided for @mapAttributionFlood.
  ///
  /// In en, this message translates to:
  /// **'Tsunami inundation: MLIT National Land Numerical Information (A40), CC BY 4.0, edited'**
  String get mapAttributionFlood;

  /// No description provided for @mapNearbySites.
  ///
  /// In en, this message translates to:
  /// **'Nearby evacuation sites'**
  String get mapNearbySites;

  /// No description provided for @mapAnyHazard.
  ///
  /// In en, this message translates to:
  /// **'Any hazard'**
  String get mapAnyHazard;

  /// No description provided for @mapWalkingDistance.
  ///
  /// In en, this message translates to:
  /// **'walking distance'**
  String get mapWalkingDistance;

  /// No description provided for @mapStraightLine.
  ///
  /// In en, this message translates to:
  /// **'straight line'**
  String get mapStraightLine;

  /// No description provided for @mapKeepsHigh.
  ///
  /// In en, this message translates to:
  /// **'keeps to higher ground'**
  String get mapKeepsHigh;

  /// No description provided for @mapBlockedConsidered.
  ///
  /// In en, this message translates to:
  /// **'blocked roads considered'**
  String get mapBlockedConsidered;

  /// No description provided for @mapAboutData.
  ///
  /// In en, this message translates to:
  /// **'About this data'**
  String get mapAboutData;

  /// No description provided for @mapMyLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get mapMyLocation;

  /// No description provided for @mapShelterHint.
  ///
  /// In en, this message translates to:
  /// **'Base: ✎ sets a site\'s status; long-press the map for a blocked road or water point.'**
  String get mapShelterHint;

  /// No description provided for @mapInFloodArea.
  ///
  /// In en, this message translates to:
  /// **'You are in the tsunami inundation area (expected {depth})'**
  String mapInFloodArea(String depth);

  /// No description provided for @mapNearFloodArea.
  ///
  /// In en, this message translates to:
  /// **'You are close to the tsunami inundation area'**
  String get mapNearFloodArea;

  /// No description provided for @mapOutsideFloodArea.
  ///
  /// In en, this message translates to:
  /// **'You are outside the tsunami inundation area'**
  String get mapOutsideFloodArea;

  /// No description provided for @mapWayOut.
  ///
  /// In en, this message translates to:
  /// **'Out of the area: {distance} walk · about {minutes} min'**
  String mapWayOut(String distance, String minutes);

  /// No description provided for @mapFloodBasis.
  ///
  /// In en, this message translates to:
  /// **'Based on the official expected inundation. A larger tsunami can go further.'**
  String get mapFloodBasis;

  /// No description provided for @mapExpectedDepth.
  ///
  /// In en, this message translates to:
  /// **'Expected depth:'**
  String get mapExpectedDepth;

  /// No description provided for @mapMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String mapMinutes(String minutes);

  /// No description provided for @mapSetStatus.
  ///
  /// In en, this message translates to:
  /// **'Set status'**
  String get mapSetStatus;

  /// No description provided for @mapAboutRoutes.
  ///
  /// In en, this message translates to:
  /// **'Distances are walking routes on OpenStreetMap roads and paths, at 60 m a minute. The route does not know about damage, crowds or tsunami height: follow official guidance and what you see. '**
  String get mapAboutRoutes;

  /// No description provided for @mapAboutHeights.
  ///
  /// In en, this message translates to:
  /// **'For tsunami the route keeps to higher ground and avoids going down, even if it is a little longer. Heights are ground heights (GSI elevation tiles): at a tsunami evacuation building, go up to the upper floors. '**
  String get mapAboutHeights;

  /// No description provided for @mapAboutStraight.
  ///
  /// In en, this message translates to:
  /// **'Distances are straight lines, not routes. '**
  String get mapAboutStraight;

  /// No description provided for @mapAboutSites.
  ///
  /// In en, this message translates to:
  /// **'Emergency evacuation sites (指定緊急避難場所) are designated per hazard; shelters (指定避難所) are for staying after the danger has passed. The data may be out of date or incomplete: check with your city.'**
  String get mapAboutSites;

  /// No description provided for @mapGsiNotes.
  ///
  /// In en, this message translates to:
  /// **'GSI usage notes (Japanese)'**
  String get mapGsiNotes;

  /// No description provided for @mapNoSiteWarning.
  ///
  /// In en, this message translates to:
  /// **'The GSI data lists no {hazard} evacuation site in {city}. The nearest site may be in another city. Check {city}\'s own hazard map and evacuation guidance.'**
  String mapNoSiteWarning(String hazard, String city);

  /// No description provided for @answerShelterComputer.
  ///
  /// In en, this message translates to:
  /// **'Base · {name}'**
  String answerShelterComputer(String name);

  /// No description provided for @answerLooking.
  ///
  /// In en, this message translates to:
  /// **'Looking in the guides…'**
  String get answerLooking;

  /// No description provided for @answerRelatedOnly.
  ///
  /// In en, this message translates to:
  /// **'The guides have related information, but no direct answer.'**
  String get answerRelatedOnly;

  /// No description provided for @answerNotCovered.
  ///
  /// In en, this message translates to:
  /// **'The installed guides do not cover this question.'**
  String get answerNotCovered;

  /// No description provided for @answerPartlyCovered.
  ///
  /// In en, this message translates to:
  /// **'Only partly covered by the guides. Check official information.'**
  String get answerPartlyCovered;

  /// No description provided for @answerUnchecked.
  ///
  /// In en, this message translates to:
  /// **'This answer could not be checked against the guides.'**
  String get answerUnchecked;

  /// No description provided for @answerSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get answerSources;

  /// No description provided for @answerBasedOn.
  ///
  /// In en, this message translates to:
  /// **'The answer is based only on these passages from official guides.'**
  String get answerBasedOn;

  /// No description provided for @answerOurTranslation.
  ///
  /// In en, this message translates to:
  /// **'Translated by {appName} (not an official translation). Show the original'**
  String answerOurTranslation(String appName);

  /// No description provided for @answerExcerpt.
  ///
  /// In en, this message translates to:
  /// **'Excerpt shown by {appName}.'**
  String answerExcerpt(String appName);

  /// No description provided for @answerGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to: {hazard} evacuation site'**
  String answerGoTo(String hazard);

  /// No description provided for @answerWayOut.
  ///
  /// In en, this message translates to:
  /// **'out of the inundation area: {distance} walk'**
  String answerWayOut(String distance);

  /// No description provided for @answerSkipped.
  ///
  /// In en, this message translates to:
  /// **'Not {site} ({distance}): {status}, {age}'**
  String answerSkipped(String site, String distance, String status, String age);

  /// No description provided for @answerSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {publisher}'**
  String answerSource(String publisher);

  /// No description provided for @answerSourceAndMore.
  ///
  /// In en, this message translates to:
  /// **'Source: {publisher} and {more} more'**
  String answerSourceAndMore(String publisher, String more);

  /// No description provided for @answerSafetyLine.
  ///
  /// In en, this message translates to:
  /// **'Safety line, quoted word for word'**
  String get answerSafetyLine;

  /// No description provided for @answerOfficialText.
  ///
  /// In en, this message translates to:
  /// **'Official text (the translation in the answer is by {appName}, not official):'**
  String answerOfficialText(String appName);

  /// No description provided for @nearestEmergencySite.
  ///
  /// In en, this message translates to:
  /// **'Nearest emergency evacuation site'**
  String get nearestEmergencySite;

  /// No description provided for @nearestSiteFor.
  ///
  /// In en, this message translates to:
  /// **'Nearest evacuation site for {hazard}'**
  String nearestSiteFor(String hazard);

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get settingsLanguageDevice;

  /// No description provided for @settingsShelter.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get settingsShelter;

  /// No description provided for @settingsOfflineData.
  ///
  /// In en, this message translates to:
  /// **'Offline data'**
  String get settingsOfflineData;

  /// No description provided for @settingsDownloadsHint.
  ///
  /// In en, this message translates to:
  /// **'AI models, safety guides and maps'**
  String get settingsDownloadsHint;

  /// No description provided for @settingsAboutGroup.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutGroup;

  /// No description provided for @settingsAboutApp.
  ///
  /// In en, this message translates to:
  /// **'About {appName}'**
  String settingsAboutApp(String appName);

  /// No description provided for @settingsAboutAppHint.
  ///
  /// In en, this message translates to:
  /// **'How it works, notes, open source'**
  String get settingsAboutAppHint;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Greek for \"small lamp\": a guide that keeps working when the network is down.'**
  String get aboutTagline;

  /// No description provided for @aboutHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get aboutHowItWorks;

  /// No description provided for @aboutOffline.
  ///
  /// In en, this message translates to:
  /// **'Works without internet'**
  String get aboutOffline;

  /// No description provided for @aboutOfflineText.
  ///
  /// In en, this message translates to:
  /// **'Answers, the map and evacuation sites all work on this device.'**
  String get aboutOfflineText;

  /// No description provided for @aboutCheckable.
  ///
  /// In en, this message translates to:
  /// **'Answers you can check'**
  String get aboutCheckable;

  /// No description provided for @aboutCheckableText.
  ///
  /// In en, this message translates to:
  /// **'Answers come from official guides and show their source. The app does not answer what the guides do not cover.'**
  String get aboutCheckableText;

  /// No description provided for @aboutFacts.
  ///
  /// In en, this message translates to:
  /// **'Current information kept apart'**
  String get aboutFacts;

  /// No description provided for @aboutFactsText.
  ///
  /// In en, this message translates to:
  /// **'Shelter status and blocked roads are shown as reported, with time and source. The AI never rewrites them.'**
  String get aboutFactsText;

  /// No description provided for @aboutPleaseNote.
  ///
  /// In en, this message translates to:
  /// **'Please note'**
  String get aboutPleaseNote;

  /// No description provided for @aboutPrototype.
  ///
  /// In en, this message translates to:
  /// **'Prototype'**
  String get aboutPrototype;

  /// No description provided for @aboutPrototypeText.
  ///
  /// In en, this message translates to:
  /// **'A research prototype. In an emergency, follow official information from your city and the Japan Meteorological Agency.'**
  String get aboutPrototypeText;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source'**
  String get aboutOpenSource;

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCode;

  /// No description provided for @aboutSourceCodeText.
  ///
  /// In en, this message translates to:
  /// **'Anyone can check and improve how it works (GNU AGPL v3). Whoever passes it on must give users the source code.'**
  String get aboutSourceCodeText;

  /// No description provided for @aboutLicences.
  ///
  /// In en, this message translates to:
  /// **'Licences'**
  String get aboutLicences;

  /// No description provided for @aboutLicencesText.
  ///
  /// In en, this message translates to:
  /// **'The app, the software and fonts it uses'**
  String get aboutLicencesText;

  /// No description provided for @aboutDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get aboutDeveloper;

  /// No description provided for @aboutShowStats.
  ///
  /// In en, this message translates to:
  /// **'Show speed and memory'**
  String get aboutShowStats;

  /// No description provided for @aboutShowStatsHint.
  ///
  /// In en, this message translates to:
  /// **'Shown under each answer.'**
  String get aboutShowStatsHint;

  /// No description provided for @noticeAi.
  ///
  /// In en, this message translates to:
  /// **'Answers are written by AI from public sources. AI can make mistakes: check the source shown with each answer.'**
  String get noticeAi;

  /// No description provided for @noticeOfficialFirst.
  ///
  /// In en, this message translates to:
  /// **'Instructions from your city, the Japan Meteorological Agency, police and fire service, and people on site who know, come first.'**
  String get noticeOfficialFirst;

  /// No description provided for @noticeNotADoctor.
  ///
  /// In en, this message translates to:
  /// **'It does not replace a doctor, and it is not a planning tool for hikes or tours.'**
  String get noticeNotADoctor;

  /// No description provided for @noticeAsk.
  ///
  /// In en, this message translates to:
  /// **'When unsure, ask someone who knows. In an emergency call 119 (ambulance, fire) or 110 (police).'**
  String get noticeAsk;

  /// No description provided for @noticeOffline.
  ///
  /// In en, this message translates to:
  /// **'It works without internet, so its information may not be the latest. It does not answer what its sources do not cover.'**
  String get noticeOffline;

  /// No description provided for @noticeAboutGuides.
  ///
  /// In en, this message translates to:
  /// **'About the guides'**
  String get noticeAboutGuides;

  /// No description provided for @noticeNewGuides.
  ///
  /// In en, this message translates to:
  /// **'New guides'**
  String get noticeNewGuides;

  /// No description provided for @askHeadline.
  ///
  /// In en, this message translates to:
  /// **'Ask anything,\neven offline.'**
  String get askHeadline;

  /// No description provided for @askIntro.
  ///
  /// In en, this message translates to:
  /// **'Answers from official safety guides for disasters and the outdoors, without internet, with the source for every answer.'**
  String get askIntro;

  /// No description provided for @askFirstDownload.
  ///
  /// In en, this message translates to:
  /// **'First: download the data'**
  String get askFirstDownload;

  /// No description provided for @askFirstDownloadText.
  ///
  /// In en, this message translates to:
  /// **'Once, on Wi-Fi. After that everything works offline.'**
  String get askFirstDownloadText;

  /// No description provided for @askGoToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Go to downloads'**
  String get askGoToDownloads;

  /// No description provided for @askTryAsking.
  ///
  /// In en, this message translates to:
  /// **'Try asking'**
  String get askTryAsking;

  /// No description provided for @askPhaseNoModel.
  ///
  /// In en, this message translates to:
  /// **'Setup needed'**
  String get askPhaseNoModel;

  /// No description provided for @askPhaseLoading.
  ///
  /// In en, this message translates to:
  /// **'Getting ready…'**
  String get askPhaseLoading;

  /// No description provided for @askPhaseReady.
  ///
  /// In en, this message translates to:
  /// **'Offline ready'**
  String get askPhaseReady;

  /// No description provided for @askPhaseShelter.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get askPhaseShelter;

  /// No description provided for @askPhaseServing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get askPhaseServing;

  /// No description provided for @askPhaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Not ready'**
  String get askPhaseFailed;

  /// No description provided for @askExplainNoModel.
  ///
  /// In en, this message translates to:
  /// **'Download the AI model and the safety guides under Settings → Downloads.'**
  String get askExplainNoModel;

  /// No description provided for @askExplainLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the AI model on this device.'**
  String get askExplainLoading;

  /// No description provided for @askExplainReady.
  ///
  /// In en, this message translates to:
  /// **'The AI runs on this device. No internet is needed.'**
  String get askExplainReady;

  /// No description provided for @askExplainShelter.
  ///
  /// In en, this message translates to:
  /// **'A base nearby (a computer) answers over the same Wi-Fi. Faster than this phone.'**
  String get askExplainShelter;

  /// No description provided for @askExplainServing.
  ///
  /// In en, this message translates to:
  /// **'This computer answers phones on the same Wi-Fi, and shares guides, maps and current information. You can stop it in Settings.'**
  String get askExplainServing;

  /// No description provided for @askExplainFailed.
  ///
  /// In en, this message translates to:
  /// **'The AI model could not be loaded.'**
  String get askExplainFailed;

  /// No description provided for @askHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a question'**
  String get askHint;

  /// No description provided for @askStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get askStop;

  /// No description provided for @askSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get askSend;

  /// No description provided for @threadsUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get threadsUndo;

  /// No description provided for @threadsNoArchived.
  ///
  /// In en, this message translates to:
  /// **'No archived conversations.'**
  String get threadsNoArchived;

  /// No description provided for @threadsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent questions'**
  String get threadsRecent;

  /// No description provided for @threadsMovedBack.
  ///
  /// In en, this message translates to:
  /// **'Moved back'**
  String get threadsMovedBack;

  /// No description provided for @threadsArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get threadsArchived;

  /// No description provided for @threadsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get threadsDeleted;

  /// No description provided for @threadsSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all ({count})'**
  String threadsSeeAll(String count);

  /// No description provided for @threadsArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get threadsArchive;

  /// No description provided for @threadsArchiveHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe right to move back, left to delete.'**
  String get threadsArchiveHint;

  /// No description provided for @threadsArchiveCount.
  ///
  /// In en, this message translates to:
  /// **'Archive ({count})'**
  String threadsArchiveCount(String count);

  /// No description provided for @threadsAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get threadsAsk;

  /// No description provided for @threadsNone.
  ///
  /// In en, this message translates to:
  /// **'No questions yet. Ask below.'**
  String get threadsNone;

  /// No description provided for @threadsSwipeHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe right to archive, left to delete.'**
  String get threadsSwipeHint;

  /// No description provided for @conversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get conversationTitle;

  /// No description provided for @packagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Answers from'**
  String get packagesTitle;

  /// No description provided for @packagesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get packagesAdd;

  /// No description provided for @packagesAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Get more packages'**
  String get packagesAddTooltip;

  /// No description provided for @shelterNoAddress.
  ///
  /// In en, this message translates to:
  /// **'No network address found. Connect this computer to Wi-Fi.'**
  String get shelterNoAddress;

  /// No description provided for @shelterConnectPhones.
  ///
  /// In en, this message translates to:
  /// **'Connect phones'**
  String get shelterConnectPhones;

  /// No description provided for @shelterScanHint.
  ///
  /// In en, this message translates to:
  /// **'On the same Wi-Fi, scan this code with the phone camera. {appName} opens and connects to \"{name}\".'**
  String shelterScanHint(String appName, String name);

  /// No description provided for @shelterOrEnterAddress.
  ///
  /// In en, this message translates to:
  /// **'Or enter the address:'**
  String get shelterOrEnterAddress;

  /// No description provided for @shelterConnectTo.
  ///
  /// In en, this message translates to:
  /// **'Connect to {name}?'**
  String shelterConnectTo(String name);

  /// No description provided for @shelterThisShelter.
  ///
  /// In en, this message translates to:
  /// **'this base'**
  String get shelterThisShelter;

  /// No description provided for @shelterConnectBody.
  ///
  /// In en, this message translates to:
  /// **'The base ({address}) will answer your questions and share current information. Only connect to a base where you are.'**
  String shelterConnectBody(String address);

  /// No description provided for @shelterConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get shelterConnect;

  /// No description provided for @shelterAddress.
  ///
  /// In en, this message translates to:
  /// **'Base address'**
  String get shelterAddress;

  /// No description provided for @shelterAddressHelper.
  ///
  /// In en, this message translates to:
  /// **'Shown on the base, under the QR code.'**
  String get shelterAddressHelper;

  /// No description provided for @shelterConnectComputer.
  ///
  /// In en, this message translates to:
  /// **'Connect to a base'**
  String get shelterConnectComputer;

  /// No description provided for @shelterConnectComputerHint.
  ///
  /// In en, this message translates to:
  /// **'Scan the base\'s QR code, or enter its address. Answers come faster.'**
  String get shelterConnectComputerHint;

  /// No description provided for @shelterAskedFirst.
  ///
  /// In en, this message translates to:
  /// **'Asked first · {address}'**
  String shelterAskedFirst(String address);

  /// No description provided for @shelterDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get shelterDisconnect;

  /// No description provided for @mapNoMap.
  ///
  /// In en, this message translates to:
  /// **'No map yet'**
  String get mapNoMap;

  /// No description provided for @mapNoMapText.
  ///
  /// In en, this message translates to:
  /// **'Download your area to see evacuation sites without internet.'**
  String get mapNoMapText;

  /// No description provided for @mapDownloadMap.
  ///
  /// In en, this message translates to:
  /// **'Download a map'**
  String get mapDownloadMap;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get navAsk;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @conversationMoveBack.
  ///
  /// In en, this message translates to:
  /// **'Move back'**
  String get conversationMoveBack;

  /// No description provided for @conversationArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get conversationArchive;

  /// No description provided for @conversationDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this conversation?'**
  String get conversationDeleteTitle;

  /// No description provided for @conversationDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'It is removed from this device.'**
  String get conversationDeleteBody;

  /// No description provided for @downloadsMobileTitle.
  ///
  /// In en, this message translates to:
  /// **'{size} over mobile data?'**
  String downloadsMobileTitle(String size);

  /// No description provided for @downloadsMobileBody.
  ///
  /// In en, this message translates to:
  /// **'Your phone is not on Wi-Fi. This uses your data plan, and with many plans it is cheaper on Wi-Fi. A base nearby, if there is one, also has the downloads on its Wi-Fi.'**
  String get downloadsMobileBody;

  /// No description provided for @downloadsMobileData.
  ///
  /// In en, this message translates to:
  /// **'Mobile data'**
  String get downloadsMobileData;

  /// No description provided for @downloadsMobileNever.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi only'**
  String get downloadsMobileNever;

  /// No description provided for @downloadsMobileAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask first'**
  String get downloadsMobileAsk;

  /// No description provided for @downloadsMobileAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get downloadsMobileAlways;

  /// No description provided for @downloadsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get downloadsFilterAll;

  /// No description provided for @downloadsFilterInstalled.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloadsFilterInstalled;

  /// No description provided for @downloadsFilterPackages.
  ///
  /// In en, this message translates to:
  /// **'Guides'**
  String get downloadsFilterPackages;

  /// No description provided for @downloadsFilterMaps.
  ///
  /// In en, this message translates to:
  /// **'Maps'**
  String get downloadsFilterMaps;

  /// No description provided for @downloadsNothingHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get downloadsNothingHere;

  /// No description provided for @downloadsSettings.
  ///
  /// In en, this message translates to:
  /// **'Download settings'**
  String get downloadsSettings;

  /// No description provided for @downloadsUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get downloadsUpdates;

  /// No description provided for @downloadsUpdatesHint.
  ///
  /// In en, this message translates to:
  /// **'New versions of guides, maps and models. \"Automatic\" downloads them by itself, on Wi-Fi only.'**
  String get downloadsUpdatesHint;

  /// No description provided for @downloadsUpdatesAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get downloadsUpdatesAuto;

  /// No description provided for @downloadsUpdatesNotify.
  ///
  /// In en, this message translates to:
  /// **'Notify'**
  String get downloadsUpdatesNotify;

  /// No description provided for @downloadsUpdatesOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get downloadsUpdatesOff;

  /// No description provided for @downloadsFilterUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates ({count})'**
  String downloadsFilterUpdates(int count);

  /// No description provided for @downloadsSigned.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get downloadsSigned;

  /// No description provided for @downloadsPublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get downloadsPublisher;

  /// No description provided for @downloadsSignedOn.
  ///
  /// In en, this message translates to:
  /// **'Signed on'**
  String get downloadsSignedOn;

  /// No description provided for @downloadsKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get downloadsKey;

  /// No description provided for @downloadsFilterKind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get downloadsFilterKind;

  /// No description provided for @webError.
  ///
  /// In en, this message translates to:
  /// **'The base could not answer. Please try again.'**
  String get webError;

  /// No description provided for @shelterWithApp.
  ///
  /// In en, this message translates to:
  /// **'With the app'**
  String get shelterWithApp;

  /// No description provided for @shelterInBrowser.
  ///
  /// In en, this message translates to:
  /// **'In the browser'**
  String get shelterInBrowser;

  /// No description provided for @shelterBrowserHint.
  ///
  /// In en, this message translates to:
  /// **'For phones without the app: opens a page from this computer. Questions and answers stay on this Wi-Fi.'**
  String get shelterBrowserHint;

  /// No description provided for @shareOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'Use this computer as a base'**
  String get shareOnNetwork;

  /// No description provided for @shareOnNetworkHint.
  ///
  /// In en, this message translates to:
  /// **'Phones on the same Wi-Fi can ask this computer, and download guides and maps from it.'**
  String get shareOnNetworkHint;

  /// No description provided for @shareName.
  ///
  /// In en, this message translates to:
  /// **'Base name'**
  String get shareName;

  /// No description provided for @shareNameHint.
  ///
  /// In en, this message translates to:
  /// **'Shown on phones (for example: Minami Elementary School shelter, a mountain hut)'**
  String get shareNameHint;

  /// No description provided for @shareStarting.
  ///
  /// In en, this message translates to:
  /// **'Starts as soon as the app is ready.'**
  String get shareStarting;

  /// No description provided for @shareShowLarge.
  ///
  /// In en, this message translates to:
  /// **'Show large'**
  String get shareShowLarge;

  /// No description provided for @shareNearby.
  ///
  /// In en, this message translates to:
  /// **'Share with people nearby'**
  String get shareNearby;

  /// No description provided for @shareNearbyIntro.
  ///
  /// In en, this message translates to:
  /// **'Phones on the same Wi-Fi or hotspot can scan this code and get the guides, maps and models downloaded to this phone. No internet needed.'**
  String get shareNearbyIntro;

  /// No description provided for @shareNearbyKeepOpen.
  ///
  /// In en, this message translates to:
  /// **'Sharing runs only while this screen is open. The screen stays on meanwhile.'**
  String get shareNearbyKeepOpen;

  /// No description provided for @shareNearbyNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing downloaded yet. You can share guides, maps and models you have downloaded.'**
  String get shareNearbyNothing;

  /// No description provided for @shareNearbyItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Sharing 1 item} other{Sharing {count} items}}'**
  String shareNearbyItems(int count);

  /// No description provided for @shareNearbySent.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Sent: 1 file} other{Sent: {count} files}}'**
  String shareNearbySent(int count);

  /// No description provided for @shareNearbyNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'Not on Wi-Fi. Connect both phones to the same Wi-Fi or hotspot.'**
  String get shareNearbyNoNetwork;

  /// No description provided for @shareReceiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Get downloads from a phone nearby?'**
  String get shareReceiveTitle;

  /// No description provided for @shareReceiveBody.
  ///
  /// In en, this message translates to:
  /// **'Shows the guides, maps and models at {address} in Downloads. They are saved only after their signatures are checked.'**
  String shareReceiveBody(String address);

  /// No description provided for @shareReceiveShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get shareReceiveShow;

  /// No description provided for @shareReceiveNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing found. Check that both phones are on the same Wi-Fi.'**
  String get shareReceiveNone;

  /// No description provided for @shareReceiveFound.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item available} other{{count} items available}}'**
  String shareReceiveFound(int count);

  /// No description provided for @shareReceiveNothingNew.
  ///
  /// In en, this message translates to:
  /// **'Nothing new: this phone already has everything offered.'**
  String get shareReceiveNothingNew;

  /// No description provided for @answerBaseUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the base, and this phone has no answer model of its own. Join the base\'s Wi-Fi and try again.'**
  String get answerBaseUnreachable;

  /// No description provided for @shareNearbyHint.
  ///
  /// In en, this message translates to:
  /// **'Pass on your downloaded guides, maps and models to phones nearby'**
  String get shareNearbyHint;

  /// No description provided for @settingsRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get settingsRegion;

  /// No description provided for @regionAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic (from your location)'**
  String get regionAuto;

  /// No description provided for @regionAutoIs.
  ///
  /// In en, this message translates to:
  /// **'Automatic: {name}'**
  String regionAutoIs(String name);

  /// No description provided for @regionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Location unknown (treated as Japan)'**
  String get regionUnknown;

  /// No description provided for @regionManual.
  ///
  /// In en, this message translates to:
  /// **'{name} (set by hand)'**
  String regionManual(String name);

  /// No description provided for @regionHint.
  ///
  /// In en, this message translates to:
  /// **'Sources for this region rank a little higher. Your location never leaves this device.'**
  String get regionHint;

  /// No description provided for @regionJapan.
  ///
  /// In en, this message translates to:
  /// **'Japan (no prefecture)'**
  String get regionJapan;

  /// No description provided for @publishersTitle.
  ///
  /// In en, this message translates to:
  /// **'Publishers'**
  String get publishersTitle;

  /// No description provided for @publishersHint.
  ///
  /// In en, this message translates to:
  /// **'Who may sign the guides and maps you install'**
  String get publishersHint;

  /// No description provided for @publishersBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built into the app'**
  String get publishersBuiltIn;

  /// No description provided for @publishersAddedOn.
  ///
  /// In en, this message translates to:
  /// **'Added {date}'**
  String publishersAddedOn(String date);

  /// No description provided for @publishersKey.
  ///
  /// In en, this message translates to:
  /// **'Key {id}'**
  String publishersKey(String id);

  /// No description provided for @publishersRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get publishersRemove;

  /// No description provided for @publishersRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String publishersRemoveTitle(String name);

  /// No description provided for @publishersRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Its guides and maps are deleted from this device. To use them again, add the publisher again and download them.'**
  String get publishersRemoveBody;

  /// No description provided for @publishersAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add this publisher?'**
  String get publishersAddTitle;

  /// No description provided for @publishersAddBody.
  ///
  /// In en, this message translates to:
  /// **'Only add publishers you know, for example your city. {app} then installs guides and maps they sign, like its own.'**
  String publishersAddBody(String app);

  /// No description provided for @publishersAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get publishersAdd;

  /// No description provided for @publishersAdded.
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String publishersAdded(String name);

  /// No description provided for @publishersFromLink.
  ///
  /// In en, this message translates to:
  /// **'Add from a link'**
  String get publishersFromLink;

  /// No description provided for @publishersLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Publisher link'**
  String get publishersLinkLabel;

  /// No description provided for @publishersNotALink.
  ///
  /// In en, this message translates to:
  /// **'This is not a publisher link.'**
  String get publishersNotALink;

  /// No description provided for @publishersBadName.
  ///
  /// In en, this message translates to:
  /// **'The link has an invalid publisher name.'**
  String get publishersBadName;

  /// No description provided for @publishersBadKey.
  ///
  /// In en, this message translates to:
  /// **'The link has an invalid key.'**
  String get publishersBadKey;

  /// No description provided for @publishersBuiltInName.
  ///
  /// In en, this message translates to:
  /// **'{name} is built into the app and cannot be added.'**
  String publishersBuiltInName(String name);

  /// No description provided for @publishersOtherKey.
  ///
  /// In en, this message translates to:
  /// **'{name} is already added with another key. If the publisher changed its key, remove it first.'**
  String publishersOtherKey(String name);

  /// No description provided for @publishersKnown.
  ///
  /// In en, this message translates to:
  /// **'{name} is already added.'**
  String publishersKnown(String name);

  /// No description provided for @publishersSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the list of publishers. Nothing was changed.'**
  String get publishersSaveFailed;

  /// No description provided for @publishersNone.
  ///
  /// In en, this message translates to:
  /// **'No other publishers yet. A city or a club that publishes its own guides gives you a link or QR code to add it.'**
  String get publishersNone;

  /// No description provided for @publishTitle.
  ///
  /// In en, this message translates to:
  /// **'Publish your own'**
  String get publishTitle;

  /// No description provided for @publishIntro.
  ///
  /// In en, this message translates to:
  /// **'Make guides and maps of your city or club available to phones. Your signing key stays on this computer; phones trust your packages after scanning your code.'**
  String get publishIntro;

  /// No description provided for @publishName.
  ///
  /// In en, this message translates to:
  /// **'Publisher name, e.g. jp.city.kobe'**
  String get publishName;

  /// No description provided for @publishNameHelp.
  ///
  /// In en, this message translates to:
  /// **'Lower case letters, digits, dots and hyphens. It cannot be changed later.'**
  String get publishNameHelp;

  /// No description provided for @publishDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Shown name, e.g. 神戸市'**
  String get publishDisplayName;

  /// No description provided for @publishCreate.
  ///
  /// In en, this message translates to:
  /// **'Create publisher key'**
  String get publishCreate;

  /// No description provided for @publishBadName.
  ///
  /// In en, this message translates to:
  /// **'Use lower case letters, digits, dots and hyphens. \'lychnion\' is taken.'**
  String get publishBadName;

  /// No description provided for @publishKeyNote.
  ///
  /// In en, this message translates to:
  /// **'The key is saved in {path}. Keep a copy offline. If it is lost, phones have to add a new key.'**
  String publishKeyNote(String path);

  /// No description provided for @publishScanHint.
  ///
  /// In en, this message translates to:
  /// **'Phones scan this code to trust your guides and maps.'**
  String get publishScanHint;

  /// No description provided for @publishCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get publishCopyLink;

  /// No description provided for @publishLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get publishLinkCopied;

  /// No description provided for @publishPick.
  ///
  /// In en, this message translates to:
  /// **'Publish a guide or map'**
  String get publishPick;

  /// No description provided for @publishKindPackage.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get publishKindPackage;

  /// No description provided for @publishKindMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get publishKindMap;

  /// No description provided for @publishId.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get publishId;

  /// No description provided for @publishVersion.
  ///
  /// In en, this message translates to:
  /// **'Version, e.g. 2026.11.1'**
  String get publishVersion;

  /// No description provided for @publishTitleJa.
  ///
  /// In en, this message translates to:
  /// **'Title (Japanese)'**
  String get publishTitleJa;

  /// No description provided for @publishTitleEn.
  ///
  /// In en, this message translates to:
  /// **'Title (English)'**
  String get publishTitleEn;

  /// No description provided for @publishLicence.
  ///
  /// In en, this message translates to:
  /// **'Licence and sources'**
  String get publishLicence;

  /// No description provided for @publishSign.
  ///
  /// In en, this message translates to:
  /// **'Sign and publish'**
  String get publishSign;

  /// No description provided for @publishDone.
  ///
  /// In en, this message translates to:
  /// **'{name} {version} published'**
  String publishDone(String name, String version);

  /// No description provided for @publishPublished.
  ///
  /// In en, this message translates to:
  /// **'Published on this computer'**
  String get publishPublished;

  /// No description provided for @publishNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing published yet.'**
  String get publishNothing;

  /// No description provided for @publishNotPackage.
  ///
  /// In en, this message translates to:
  /// **'This file is not a package file.'**
  String get publishNotPackage;

  /// No description provided for @publishErrorId.
  ///
  /// In en, this message translates to:
  /// **'The ID may only use letters, digits, dots, hyphens and underscores.'**
  String get publishErrorId;

  /// No description provided for @publishErrorVersion.
  ///
  /// In en, this message translates to:
  /// **'The version must be numbers with dots, e.g. 2026.11.1.'**
  String get publishErrorVersion;

  /// No description provided for @publishErrorOlder.
  ///
  /// In en, this message translates to:
  /// **'Version {have} is already published or installed. Use a higher version.'**
  String publishErrorOlder(String have);

  /// No description provided for @publishErrorFiles.
  ///
  /// In en, this message translates to:
  /// **'Every file name must start with the ID and a dot. A guide is one file.'**
  String get publishErrorFiles;

  /// No description provided for @publishErrorMeta.
  ///
  /// In en, this message translates to:
  /// **'ID and version must match the package file.'**
  String get publishErrorMeta;

  /// No description provided for @publishErrorTaken.
  ///
  /// In en, this message translates to:
  /// **'This ID is installed from {publisher}. Use another ID.'**
  String publishErrorTaken(String publisher);

  /// No description provided for @publishErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Give a title.'**
  String get publishErrorTitle;

  /// No description provided for @publishErrorKey.
  ///
  /// In en, this message translates to:
  /// **'Another key is added under this publisher name. Remove it in Publishers first.'**
  String get publishErrorKey;

  /// No description provided for @publishFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not publish: {detail}'**
  String publishFailed(String detail);

  /// No description provided for @publishKeyUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The key file {path} cannot be read. Put back your copy of it. A new key would mean that phones have to add your publisher again.'**
  String publishKeyUnreadable(String path);

  /// No description provided for @publishKeyExists.
  ///
  /// In en, this message translates to:
  /// **'A key file is already there. It is never replaced.'**
  String get publishKeyExists;

  /// No description provided for @publishKeyPrivateFailed.
  ///
  /// In en, this message translates to:
  /// **'The key file could not be made private, so no key was made.'**
  String get publishKeyPrivateFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
