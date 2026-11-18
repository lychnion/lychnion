// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Lychnion';

  @override
  String get settings => 'Settings';

  @override
  String get beforeYouStart => 'Before you start';

  @override
  String get iUnderstand => 'I understand';

  @override
  String get downloadsErrorOffline => 'No internet connection.';

  @override
  String get downloadsErrorWifiOnly =>
      'Connect to Wi-Fi (mobile data is off in the setting above).';

  @override
  String get downloadsErrorNetwork =>
      'The connection dropped. \"Resume\" continues where it stopped.';

  @override
  String get downloadsErrorChecksum =>
      'The file was damaged and has been removed. Please download again.';

  @override
  String get downloadsErrorChecksumLocal =>
      'This file does not match the catalog. Delete it and download again.';

  @override
  String get downloadsErrorBusy => 'Already downloading in another window.';

  @override
  String get downloadsErrorDiskFull => 'Not enough free space.';

  @override
  String get downloadsErrorDisk => 'Could not save the file.';

  @override
  String get downloadsErrorSignature =>
      'This download is not signed by Lychnion, so it was not installed.';

  @override
  String get downloadsErrorOlder =>
      'This is an older version than the one installed, so it was not installed.';

  @override
  String downloadsLargeWarning(String size) {
    return 'This downloads $size. Please use Wi-Fi. You need at least $size of free space. If it stops, you can resume where it left off.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get downloadsDownload => 'Download';

  @override
  String get downloadsDeleteTitle => 'Delete?';

  @override
  String downloadsDeleteBody(String title, String size) {
    return 'Removes $title ($size) from this device. You cannot get it back while offline.';
  }

  @override
  String get delete => 'Delete';

  @override
  String get downloadsTitle => 'Downloads';

  @override
  String get downloadsWifiOnlyHint =>
      'Models and maps can be several GB. \"Ask first\" asks before each download over mobile data.';

  @override
  String get downloadsFooter =>
      'Everything downloaded works offline. Files are checked (SHA-256) before the app uses them.';

  @override
  String get downloadsKindModels => 'Models';

  @override
  String get downloadsKindPackages => 'Knowledge packages';

  @override
  String get downloadsKindMaps => 'Map areas';

  @override
  String get downloadsTooLargeForPhone => 'Too large for most phones.';

  @override
  String get downloadsNotDownloaded => 'Not downloaded';

  @override
  String get downloadsNoSource =>
      'No download source yet (uses the copy in the app)';

  @override
  String downloadsPaused(String done, String total) {
    return 'Paused: $done of $total';
  }

  @override
  String get downloadsUnverified => 'File present (not checked yet)';

  @override
  String get downloadsInstalled => 'Downloaded and checked';

  @override
  String downloadsUpdateAvailable(String version) {
    return 'Update available (on device: $version)';
  }

  @override
  String get downloadsStop => 'Stop';

  @override
  String get downloadsResume => 'Resume';

  @override
  String get downloadsUpdate => 'Update';

  @override
  String get downloadsCheckFile => 'Check file';

  @override
  String get downloadsInUse => 'In use';

  @override
  String get downloadsUseModel => 'Use this model';

  @override
  String get downloadsCheckingPart => 'Checking the part already downloaded…';

  @override
  String downloadsVerifying(String percent) {
    return 'Checking the checksum… $percent%';
  }

  @override
  String get downloadsEtaOneMinute => 'about 1 min left';

  @override
  String downloadsEtaMinutes(String minutes) {
    return 'about $minutes min left';
  }

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(String minutes) {
    return '$minutes min ago';
  }

  @override
  String hoursAgo(String hours) {
    return '$hours h ago';
  }

  @override
  String daysAgo(String days) {
    return '$days days ago';
  }

  @override
  String get factSourceOfficialUnverified => 'says official, not verified';

  @override
  String get factSourceSensorUnverified => 'says sensor, not verified';

  @override
  String get factSourceOfficial => 'official';

  @override
  String get factSourceSensor => 'sensor';

  @override
  String get factSourceCitizen => 'resident report, unconfirmed';

  @override
  String shelterStatus(String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'open': 'open',
      'crowded': 'crowded',
      'full': 'full',
      'closed': 'closed',
      'other': '$status',
    });
    return '$_temp0';
  }

  @override
  String get factRoadBlocked => 'road blocked';

  @override
  String factWater(String value) {
    return 'water: $value';
  }

  @override
  String get factUnconfirmed => 'unconfirmed';

  @override
  String get factsBoxTitle => 'Current information · not from the AI';

  @override
  String get factsBoxRoadBlocked => 'Road blocked';

  @override
  String factsBoxWater(String value) {
    return 'Water: $value';
  }

  @override
  String get factsBoxAddWarning => 'Add warning';

  @override
  String get factFormWarning => 'Warning (e.g. 津波警報)';

  @override
  String get factFormNote => 'Note (optional)';

  @override
  String get factFormValidFor => 'Valid for';

  @override
  String factFormHours(String hours) {
    return '$hours h';
  }

  @override
  String get factFormOfficial => 'Official (staff, city)';

  @override
  String get factFormResident => 'Resident report';

  @override
  String get factFormClear => 'No longer true';

  @override
  String get save => 'Save';

  @override
  String hazardName(String hazard) {
    String _temp0 = intl.Intl.selectLogic(hazard, {
      'tsunami': 'Tsunami',
      'earthquake': 'Earthquake',
      'flood': 'Flood',
      'landslide': 'Landslide',
      'stormSurge': 'Storm surge',
      'fire': 'Large fire',
      'inlandFlood': 'Inland flooding',
      'volcano': 'Volcano',
      'other': '$hazard',
    });
    return '$_temp0';
  }

  @override
  String hazardInSentence(String hazard) {
    String _temp0 = intl.Intl.selectLogic(hazard, {
      'tsunami': 'tsunami',
      'earthquake': 'earthquake',
      'flood': 'flood',
      'landslide': 'landslide',
      'stormSurge': 'storm surge',
      'fire': 'large fire',
      'inlandFlood': 'inland flooding',
      'volcano': 'volcano',
      'other': '$hazard',
    });
    return '$_temp0';
  }

  @override
  String compassPoint(String point) {
    String _temp0 = intl.Intl.selectLogic(point, {
      'n': 'N',
      'ne': 'NE',
      'e': 'E',
      'se': 'SE',
      's': 'S',
      'sw': 'SW',
      'w': 'W',
      'nw': 'NW',
      'other': '$point',
    });
    return '$_temp0';
  }

  @override
  String siteHeight(String height) {
    return '$height m above sea level';
  }

  @override
  String siteFlooding(String depth) {
    return 'expected flooding $depth';
  }

  @override
  String siteDip(String height) {
    return 'dips to $height m on the way';
  }

  @override
  String siteWalk(String distance, String minutes) {
    return '$distance walk · about $minutes min';
  }

  @override
  String siteStraight(String distance, String direction) {
    return '$distance $direction · straight line';
  }

  @override
  String depthOrMore(String lo) {
    return '$lo m or more';
  }

  @override
  String depthUnder(String hi) {
    return 'under $hi m';
  }

  @override
  String depthRange(String lo, String hi) {
    return '$lo–$hi m';
  }

  @override
  String get depthLegendUnder => 'under 0.3 m';

  @override
  String depthLegendFrom(String lo) {
    return 'from $lo m';
  }

  @override
  String mapWarningFor(String city) {
    return 'Warning for $city';
  }

  @override
  String get mapRoadBlockedHere => 'Road blocked here';

  @override
  String get mapWaterHere => 'Water handed out here';

  @override
  String get mapRoadBlocked => 'Road blocked';

  @override
  String get mapWaterPoint => 'Water point';

  @override
  String get mapWaterTruck => 'water truck';

  @override
  String get mapWaterStation => 'water station';

  @override
  String get mapWhichHazard => 'Which hazard?';

  @override
  String get mapTestLocation => 'Test location';

  @override
  String mapLocationAccuracy(String meters) {
    return 'Location ±$meters m';
  }

  @override
  String get mapNoLocationPermission => 'No location permission';

  @override
  String get mapNoLocation => 'Location not available';

  @override
  String get mapHazard => 'Hazard';

  @override
  String get mapChooseHazard => 'Choose the hazard';

  @override
  String get mapAttributionSites => 'Evacuation sites: GSI Japan';

  @override
  String get mapAttributionHeights => 'Heights: GSI elevation tiles';

  @override
  String get mapAttributionFlood =>
      'Tsunami inundation: MLIT National Land Numerical Information (A40), CC BY 4.0, edited';

  @override
  String get mapNearbySites => 'Nearby evacuation sites';

  @override
  String get mapAnyHazard => 'Any hazard';

  @override
  String get mapWalkingDistance => 'walking distance';

  @override
  String get mapStraightLine => 'straight line';

  @override
  String get mapKeepsHigh => 'keeps to higher ground';

  @override
  String get mapBlockedConsidered => 'blocked roads considered';

  @override
  String get mapAboutData => 'About this data';

  @override
  String get mapMyLocation => 'My location';

  @override
  String get mapShelterHint =>
      'Shelter computer: ✎ sets a site\'s status; long-press the map for a blocked road or water point.';

  @override
  String mapInFloodArea(String depth) {
    return 'You are in the tsunami inundation area (expected $depth)';
  }

  @override
  String get mapNearFloodArea => 'You are close to the tsunami inundation area';

  @override
  String get mapOutsideFloodArea =>
      'You are outside the tsunami inundation area';

  @override
  String mapWayOut(String distance, String minutes) {
    return 'Out of the area: $distance walk · about $minutes min';
  }

  @override
  String get mapFloodBasis =>
      'Based on the official expected inundation. A larger tsunami can go further.';

  @override
  String get mapExpectedDepth => 'Expected depth:';

  @override
  String mapMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String get mapSetStatus => 'Set status';

  @override
  String get mapAboutRoutes =>
      'Distances are walking routes on OpenStreetMap roads and paths, at 60 m a minute. The route does not know about damage, crowds or tsunami height: follow official guidance and what you see. ';

  @override
  String get mapAboutHeights =>
      'For tsunami the route keeps to higher ground and avoids going down, even if it is a little longer. Heights are ground heights (GSI elevation tiles): at a tsunami evacuation building, go up to the upper floors. ';

  @override
  String get mapAboutStraight => 'Distances are straight lines, not routes. ';

  @override
  String get mapAboutSites =>
      'Emergency evacuation sites (指定緊急避難場所) are designated per hazard; shelters (指定避難所) are for staying after the danger has passed. The data may be out of date or incomplete: check with your city.';

  @override
  String get mapGsiNotes => 'GSI usage notes (Japanese)';

  @override
  String mapNoSiteWarning(String hazard, String city) {
    return 'The GSI data lists no $hazard evacuation site in $city. The nearest site may be in another city. Check $city\'s own hazard map and evacuation guidance.';
  }

  @override
  String answerShelterComputer(String name) {
    return 'Shelter computer · $name';
  }

  @override
  String get answerLooking => 'Looking in the guides…';

  @override
  String get answerRelatedOnly =>
      'The guides have related information, but no direct answer.';

  @override
  String get answerNotCovered =>
      'The installed guides do not cover this question.';

  @override
  String get answerPartlyCovered =>
      'Only partly covered by the guides. Check official information.';

  @override
  String get answerUnchecked =>
      'This answer could not be checked against the guides.';

  @override
  String get answerSources => 'Sources';

  @override
  String get answerBasedOn =>
      'The answer is based only on these passages from official guides.';

  @override
  String answerOurTranslation(String appName) {
    return 'Translated by $appName (not an official translation). Show the original';
  }

  @override
  String answerExcerpt(String appName) {
    return 'Excerpt shown by $appName.';
  }

  @override
  String answerGoTo(String hazard) {
    return 'Go to: $hazard evacuation site';
  }

  @override
  String answerWayOut(String distance) {
    return 'out of the inundation area: $distance walk';
  }

  @override
  String answerSkipped(
    String site,
    String distance,
    String status,
    String age,
  ) {
    return 'Not $site ($distance): $status, $age';
  }

  @override
  String answerSource(String publisher) {
    return 'Source: $publisher';
  }

  @override
  String answerSourceAndMore(String publisher, String more) {
    return 'Source: $publisher and $more more';
  }

  @override
  String get answerSafetyLine => 'Safety line, quoted word for word';

  @override
  String answerOfficialText(String appName) {
    return 'Official text (the translation in the answer is by $appName, not official):';
  }

  @override
  String get nearestEmergencySite => 'Nearest emergency evacuation site';

  @override
  String nearestSiteFor(String hazard) {
    return 'Nearest evacuation site for $hazard';
  }

  @override
  String get languageName => 'English';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageDevice => 'Device';

  @override
  String get settingsShelter => 'Shelter';

  @override
  String get settingsOfflineData => 'Offline data';

  @override
  String get settingsDownloadsHint => 'AI models, safety guides and maps';

  @override
  String get settingsAboutGroup => 'About';

  @override
  String settingsAboutApp(String appName) {
    return 'About $appName';
  }

  @override
  String get settingsAboutAppHint => 'How it works, notes, open source';

  @override
  String get aboutTagline =>
      'Greek for \"small lamp\": a guide that keeps working when the network is down.';

  @override
  String get aboutHowItWorks => 'How it works';

  @override
  String get aboutOffline => 'Works without internet';

  @override
  String get aboutOfflineText =>
      'Answers, the map and evacuation sites all work on this device.';

  @override
  String get aboutCheckable => 'Answers you can check';

  @override
  String get aboutCheckableText =>
      'Answers come from official guides and show their source. The app does not answer what the guides do not cover.';

  @override
  String get aboutFacts => 'Current information kept apart';

  @override
  String get aboutFactsText =>
      'Shelter status and blocked roads are shown as reported, with time and source. The AI never rewrites them.';

  @override
  String get aboutPleaseNote => 'Please note';

  @override
  String get aboutPrototype => 'Prototype';

  @override
  String get aboutPrototypeText =>
      'A research prototype. In an emergency, follow official information from your city and the Japan Meteorological Agency.';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutSourceCode => 'Source code';

  @override
  String get aboutSourceCodeText =>
      'Anyone can check and improve how it works (GNU AGPL v3). Whoever passes it on must give users the source code.';

  @override
  String get aboutLicences => 'Licences';

  @override
  String get aboutLicencesText => 'The app, the software and fonts it uses';

  @override
  String get aboutDeveloper => 'Developer';

  @override
  String get aboutShowStats => 'Show speed and memory';

  @override
  String get aboutShowStatsHint => 'Shown under each answer.';

  @override
  String get noticeAi =>
      'Answers are written by AI from public sources. AI can make mistakes: check the source shown with each answer.';

  @override
  String get noticeOfficialFirst =>
      'Instructions from your city, the Japan Meteorological Agency, police and fire service, and people on site who know, come first.';

  @override
  String get noticeNotADoctor =>
      'It does not replace a doctor, and it is not a planning tool for hikes or tours.';

  @override
  String get noticeAsk =>
      'When unsure, ask someone who knows. In an emergency call 119 (ambulance, fire) or 110 (police).';

  @override
  String get noticeOffline =>
      'It works without internet, so its information may not be the latest. It does not answer what its sources do not cover.';

  @override
  String get noticeAboutGuides => 'About the guides';

  @override
  String get noticeNewGuides => 'New guides';

  @override
  String get askHeadline => 'Ask anything,\neven offline.';

  @override
  String get askIntro =>
      'Answers from official safety guides for disasters and the outdoors, without internet, with the source for every answer.';

  @override
  String get askFirstDownload => 'First: download the data';

  @override
  String get askFirstDownloadText =>
      'Once, on Wi-Fi. After that everything works offline.';

  @override
  String get askGoToDownloads => 'Go to downloads';

  @override
  String get askTryAsking => 'Try asking';

  @override
  String get askPhaseNoModel => 'Setup needed';

  @override
  String get askPhaseLoading => 'Getting ready…';

  @override
  String get askPhaseReady => 'Offline ready';

  @override
  String get askPhaseShelter => 'Shelter';

  @override
  String get askPhaseServing => 'Sharing';

  @override
  String get askPhaseFailed => 'Not ready';

  @override
  String get askExplainNoModel =>
      'Download the AI model and the safety guides under Settings → Downloads.';

  @override
  String get askExplainLoading => 'Loading the AI model on this device.';

  @override
  String get askExplainReady =>
      'The AI runs on this device. No internet is needed.';

  @override
  String get askExplainShelter =>
      'A computer at the shelter answers, over the local Wi-Fi. Faster than this phone.';

  @override
  String get askExplainServing =>
      'This computer answers phones on the same Wi-Fi, and shares guides, maps and current information. You can stop it in Settings.';

  @override
  String get askExplainFailed => 'The AI model could not be loaded.';

  @override
  String get askHint => 'Ask a question';

  @override
  String get askStop => 'Stop';

  @override
  String get askSend => 'Send';

  @override
  String get threadsUndo => 'Undo';

  @override
  String get threadsNoArchived => 'No archived conversations.';

  @override
  String get threadsRecent => 'Recent questions';

  @override
  String get threadsMovedBack => 'Moved back';

  @override
  String get threadsArchived => 'Archived';

  @override
  String get threadsDeleted => 'Deleted';

  @override
  String threadsSeeAll(String count) {
    return 'See all ($count)';
  }

  @override
  String get threadsArchive => 'Archive';

  @override
  String get threadsArchiveHint => 'Swipe right to move back, left to delete.';

  @override
  String threadsArchiveCount(String count) {
    return 'Archive ($count)';
  }

  @override
  String get threadsAsk => 'Ask';

  @override
  String get threadsNone => 'No questions yet. Ask below.';

  @override
  String get threadsSwipeHint => 'Swipe right to archive, left to delete.';

  @override
  String get conversationTitle => 'Conversation';

  @override
  String get packagesTitle => 'Answers from';

  @override
  String get packagesAdd => 'Add';

  @override
  String get packagesAddTooltip => 'Get more packages';

  @override
  String get shelterNoAddress =>
      'No network address found. Connect this computer to the shelter Wi-Fi.';

  @override
  String get shelterConnectPhones => 'Connect phones';

  @override
  String shelterScanHint(String appName, String name) {
    return 'On the shelter Wi-Fi, scan this code with the phone camera. $appName opens and connects to \"$name\".';
  }

  @override
  String get shelterOrEnterAddress => 'Or enter the address:';

  @override
  String shelterConnectTo(String name) {
    return 'Connect to $name?';
  }

  @override
  String get shelterThisShelter => 'this shelter';

  @override
  String shelterConnectBody(String address) {
    return 'The shelter computer ($address) will answer your questions and share current information. Only connect to a shelter you are at.';
  }

  @override
  String get shelterConnect => 'Connect';

  @override
  String get shelterAddress => 'Shelter address';

  @override
  String get shelterAddressHelper =>
      'Shown on the shelter computer, under the QR code.';

  @override
  String get shelterConnectComputer => 'Connect to a shelter computer';

  @override
  String get shelterConnectComputerHint =>
      'Scan the QR code at the shelter, or enter its address. Answers come faster.';

  @override
  String shelterAskedFirst(String address) {
    return 'Asked first · $address';
  }

  @override
  String get shelterDisconnect => 'Disconnect';

  @override
  String get mapNoMap => 'No map yet';

  @override
  String get mapNoMapText =>
      'Download your area to see evacuation sites without internet.';

  @override
  String get mapDownloadMap => 'Download a map';

  @override
  String get navHome => 'Home';

  @override
  String get navAsk => 'Ask';

  @override
  String get navMap => 'Map';

  @override
  String get conversationMoveBack => 'Move back';

  @override
  String get conversationArchive => 'Archive';

  @override
  String get conversationDeleteTitle => 'Delete this conversation?';

  @override
  String get conversationDeleteBody => 'It is removed from this device.';

  @override
  String downloadsMobileTitle(String size) {
    return '$size over mobile data?';
  }

  @override
  String get downloadsMobileBody =>
      'Your phone is not on Wi-Fi. This uses your data plan, and with many plans it is cheaper on Wi-Fi. A shelter computer, if there is one nearby, also has the downloads on its Wi-Fi.';

  @override
  String get downloadsMobileData => 'Mobile data';

  @override
  String get downloadsMobileNever => 'Wi-Fi only';

  @override
  String get downloadsMobileAsk => 'Ask first';

  @override
  String get downloadsMobileAlways => 'Always';

  @override
  String get downloadsFilterAll => 'All';

  @override
  String get downloadsFilterInstalled => 'Downloaded';

  @override
  String get downloadsFilterPackages => 'Guides';

  @override
  String get downloadsFilterMaps => 'Maps';

  @override
  String get downloadsNothingHere => 'Nothing here yet.';

  @override
  String get downloadsSettings => 'Download settings';

  @override
  String get downloadsUpdates => 'Updates';

  @override
  String get downloadsUpdatesHint =>
      'New versions of guides, maps and models. \"Automatic\" downloads them by itself, on Wi-Fi only.';

  @override
  String get downloadsUpdatesAuto => 'Automatic';

  @override
  String get downloadsUpdatesNotify => 'Notify';

  @override
  String get downloadsUpdatesOff => 'Off';

  @override
  String downloadsFilterUpdates(int count) {
    return 'Updates ($count)';
  }

  @override
  String get downloadsSigned => 'Signed';

  @override
  String get downloadsPublisher => 'Publisher';

  @override
  String get downloadsSignedOn => 'Signed on';

  @override
  String get downloadsKey => 'Key';

  @override
  String get downloadsFilterKind => 'Kind';

  @override
  String get webError =>
      'The shelter computer could not answer. Please try again.';

  @override
  String get shelterWithApp => 'With the app';

  @override
  String get shelterInBrowser => 'In the browser';

  @override
  String get shelterBrowserHint =>
      'For phones without the app: opens a page from this computer. Questions and answers stay on the shelter Wi-Fi.';

  @override
  String get shareOnNetwork => 'Share on the local network';

  @override
  String get shareOnNetworkHint =>
      'Phones on the same Wi-Fi can ask this computer, and download guides and maps from it.';

  @override
  String get shareName => 'Shelter name';

  @override
  String get shareNameHint =>
      'Shown on phones (for example: Minami Elementary School shelter)';

  @override
  String get shareStarting => 'Starts as soon as the app is ready.';

  @override
  String get shareShowLarge => 'Show large';
}
