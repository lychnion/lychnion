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
  String get downloadsErrorTaken =>
      'This ID or one of its files is already installed from another publisher, so it was not installed.';

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
      'Base: ✎ sets a site\'s status; long-press the map for a blocked road or water point.';

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
    return 'Base · $name';
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
  String get settingsShelter => 'Base';

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
  String get askPhaseShelter => 'Base';

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
      'A base nearby (a computer) answers over the same Wi-Fi. Faster than this phone.';

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
      'No network address found. Connect this computer to Wi-Fi.';

  @override
  String get shelterConnectPhones => 'Connect phones';

  @override
  String shelterScanHint(String appName, String name) {
    return 'On the same Wi-Fi, scan this code with the phone camera. $appName opens and connects to \"$name\".';
  }

  @override
  String get shelterOrEnterAddress => 'Or enter the address:';

  @override
  String shelterConnectTo(String name) {
    return 'Connect to $name?';
  }

  @override
  String get shelterThisShelter => 'this base';

  @override
  String shelterConnectBody(String address) {
    return 'The base ($address) will answer your questions and share current information. Only connect to a base where you are.';
  }

  @override
  String get shelterConnect => 'Connect';

  @override
  String get shelterAddress => 'Base address';

  @override
  String get shelterAddressHelper => 'Shown on the base, under the QR code.';

  @override
  String get shelterConnectComputer => 'Connect to a base';

  @override
  String get shelterConnectComputerHint =>
      'Scan the base\'s QR code, or enter its address. Answers come faster.';

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
      'Your phone is not on Wi-Fi. This uses your data plan, and with many plans it is cheaper on Wi-Fi. A base nearby, if there is one, also has the downloads on its Wi-Fi.';

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
  String get webError => 'The base could not answer. Please try again.';

  @override
  String get shelterWithApp => 'With the app';

  @override
  String get shelterInBrowser => 'In the browser';

  @override
  String get shelterBrowserHint =>
      'For phones without the app: opens a page from this computer. Questions and answers stay on this Wi-Fi.';

  @override
  String get shareOnNetwork => 'Use this computer as a base';

  @override
  String get shareOnNetworkHint =>
      'Phones on the same Wi-Fi can ask this computer, and download guides and maps from it.';

  @override
  String get shareName => 'Base name';

  @override
  String get shareNameHint =>
      'Shown on phones (for example: Minami Elementary School shelter, a mountain hut)';

  @override
  String get shareStarting => 'Starts as soon as the app is ready.';

  @override
  String get shareShowLarge => 'Show large';

  @override
  String get shareNearby => 'Share with people nearby';

  @override
  String get shareNearbyIntro =>
      'Phones on the same Wi-Fi or hotspot can scan this code and get the guides, maps and models downloaded to this phone. No internet needed.';

  @override
  String get shareNearbyKeepOpen =>
      'Sharing runs only while this screen is open. The screen stays on meanwhile.';

  @override
  String get shareNearbyNothing =>
      'Nothing downloaded yet. You can share guides, maps and models you have downloaded.';

  @override
  String shareNearbyItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sharing $count items',
      one: 'Sharing 1 item',
    );
    return '$_temp0';
  }

  @override
  String shareNearbySent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sent: $count files',
      one: 'Sent: 1 file',
    );
    return '$_temp0';
  }

  @override
  String get shareNearbyNoNetwork =>
      'Not on Wi-Fi. Connect both phones to the same Wi-Fi or hotspot.';

  @override
  String get shareReceiveTitle => 'Get downloads from a phone nearby?';

  @override
  String shareReceiveBody(String address) {
    return 'Shows the guides, maps and models at $address in Downloads. They are saved only after their signatures are checked.';
  }

  @override
  String get shareReceiveShow => 'Show';

  @override
  String get shareReceiveNone =>
      'Nothing found. Check that both phones are on the same Wi-Fi.';

  @override
  String shareReceiveFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items available',
      one: '1 item available',
    );
    return '$_temp0';
  }

  @override
  String get shareReceiveNothingNew =>
      'Nothing new: this phone already has everything offered.';

  @override
  String get answerBaseUnreachable =>
      'Can\'t reach the base, and this phone has no answer model of its own. Join the base\'s Wi-Fi and try again.';

  @override
  String get shareNearbyHint =>
      'Pass on your downloaded guides, maps and models to phones nearby';

  @override
  String get settingsRegion => 'Region';

  @override
  String get regionAuto => 'Automatic (from your location)';

  @override
  String regionAutoIs(String name) {
    return 'Automatic: $name';
  }

  @override
  String get regionUnknown => 'Location unknown (treated as Japan)';

  @override
  String regionManual(String name) {
    return '$name (set by hand)';
  }

  @override
  String get regionHint =>
      'Sources for this region rank a little higher. Your location never leaves this device.';

  @override
  String get regionJapan => 'Japan (no prefecture)';

  @override
  String get areaJapan => 'Japan';

  @override
  String get publishersTitle => 'Publishers';

  @override
  String get publishersHint => 'Who may sign the guides and maps you install';

  @override
  String get publishersBuiltIn => 'Built into the app';

  @override
  String publishersAddedOn(String date) {
    return 'Added $date';
  }

  @override
  String publishersKey(String id) {
    return 'Key $id';
  }

  @override
  String get publishersRemove => 'Remove';

  @override
  String publishersRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get publishersRemoveBody =>
      'Its guides and maps are deleted from this device. To use them again, add the publisher again and download them.';

  @override
  String get publishersAddTitle => 'Add this publisher?';

  @override
  String publishersAddBody(String app) {
    return 'Only add publishers you know, for example your city. $app then installs guides and maps they sign, like its own.';
  }

  @override
  String get publishersAdd => 'Add';

  @override
  String publishersAdded(String name) {
    return '$name added';
  }

  @override
  String get publishersFromLink => 'Add from a link';

  @override
  String get publishersLinkLabel => 'Publisher link';

  @override
  String get publishersNotALink => 'This is not a publisher link.';

  @override
  String get publishersBadName => 'The link has an invalid publisher name.';

  @override
  String get publishersBadKey => 'The link has an invalid key.';

  @override
  String publishersBuiltInName(String name) {
    return '$name is built into the app and cannot be added.';
  }

  @override
  String publishersOtherKey(String name) {
    return '$name is already added with another key. If the publisher changed its key, remove it first.';
  }

  @override
  String publishersKnown(String name) {
    return '$name is already added.';
  }

  @override
  String get publishersSaveFailed =>
      'Could not save the list of publishers. Nothing was changed.';

  @override
  String get publishersNone =>
      'No other publishers yet. A city or a club that publishes its own guides gives you a link or QR code to add it.';

  @override
  String get publishTitle => 'Publish your own';

  @override
  String get publishIntro =>
      'Make guides and maps of your city or club available to phones. Your signing key stays on this computer; phones trust your packages after scanning your code.';

  @override
  String get publishName => 'Publisher name, e.g. jp.city.kobe';

  @override
  String get publishNameHelp =>
      'Lower case letters, digits, dots and hyphens. It cannot be changed later.';

  @override
  String get publishDisplayName => 'Shown name, e.g. 神戸市';

  @override
  String get publishCreate => 'Create publisher key';

  @override
  String get publishBadName =>
      'Use lower case letters, digits, dots and hyphens. \'lychnion\' is taken.';

  @override
  String publishKeyNote(String path) {
    return 'The key is saved in $path. Keep a copy offline. If it is lost, phones have to add a new key.';
  }

  @override
  String get publishScanHint =>
      'Phones scan this code to trust your guides and maps.';

  @override
  String get publishCopyLink => 'Copy link';

  @override
  String get publishLinkCopied => 'Link copied';

  @override
  String get publishPick => 'Publish a guide or map';

  @override
  String get publishKindPackage => 'Guide';

  @override
  String get publishKindMap => 'Map';

  @override
  String get publishId => 'ID';

  @override
  String get publishVersion => 'Version, e.g. 2026.11.1';

  @override
  String get publishTitleJa => 'Title (Japanese)';

  @override
  String get publishTitleEn => 'Title (English)';

  @override
  String get publishLicence => 'Licence and sources';

  @override
  String get publishSign => 'Sign and publish';

  @override
  String publishDone(String name, String version) {
    return '$name $version published';
  }

  @override
  String get publishPublished => 'Published on this computer';

  @override
  String get publishNothing => 'Nothing published yet.';

  @override
  String get publishNotPackage => 'This file is not a package file.';

  @override
  String get publishErrorId =>
      'The ID may only use letters, digits, dots, hyphens and underscores.';

  @override
  String get publishErrorVersion =>
      'The version must be numbers with dots, e.g. 2026.11.1.';

  @override
  String publishErrorOlder(String have) {
    return 'Version $have is already published or installed. Use a higher version.';
  }

  @override
  String get publishErrorFiles =>
      'Every file name must start with the ID and a dot. A guide is one file.';

  @override
  String get publishErrorMeta => 'ID and version must match the package file.';

  @override
  String publishErrorTaken(String publisher) {
    return 'This ID is installed from $publisher. Use another ID.';
  }

  @override
  String get publishErrorTitle => 'Give a title.';

  @override
  String get publishErrorKey =>
      'Another key is added under this publisher name. Remove it in Publishers first.';

  @override
  String publishFailed(String detail) {
    return 'Could not publish: $detail';
  }

  @override
  String publishKeyUnreadable(String path) {
    return 'The key file $path cannot be read. Put back your copy of it. A new key would mean that phones have to add your publisher again.';
  }

  @override
  String get publishKeyExists =>
      'A key file is already there. It is never replaced.';

  @override
  String get publishKeyPrivateFailed =>
      'The key file could not be made private, so no key was made.';

  @override
  String get catalogsTitle => 'Catalogs';

  @override
  String catalogsHint(String app) {
    return 'Lists of guides and maps from cities and clubs, next to $app\'s';
  }

  @override
  String get catalogsNone =>
      'No other catalogs yet. A city or club that offers its own guides gives you a link or QR code.';

  @override
  String get catalogsAdd => 'Follow a catalog';

  @override
  String get catalogsUrlLabel => 'Catalog address or link';

  @override
  String get catalogsNotALink => 'This is not a catalog address.';

  @override
  String get catalogsAddTitle => 'Follow this catalog?';

  @override
  String catalogsAddBody(String app) {
    return 'Its guides and maps appear in Downloads. $app only shows those signed by itself or by a publisher you added.';
  }

  @override
  String get catalogsFollow => 'Follow';

  @override
  String catalogsStatus(String shown, String notShown) {
    return '$shown shown · $notShown not shown';
  }

  @override
  String get catalogsNotShownHint =>
      'Not shown: from a publisher you have not added, not validly signed, or an ID that belongs to another publisher.';

  @override
  String catalogsFetched(String date) {
    return 'Updated $date';
  }

  @override
  String get catalogsNeverFetched => 'Not loaded yet';

  @override
  String catalogsError(String error) {
    return 'Could not load ($error); the last copy is used.';
  }

  @override
  String get catalogsRemove => 'Stop following';

  @override
  String catalogsRemoveTitle(String name) {
    return 'Stop following $name?';
  }

  @override
  String get catalogsRemoveBody =>
      'Its items no longer appear in Downloads. What you installed from it stays.';

  @override
  String get catalogsKnown =>
      'This catalog is followed already, or the list is full.';

  @override
  String get catalogsSaveFailed =>
      'Could not save the list of catalogs. Nothing was changed.';

  @override
  String get catalogsRefresh => 'Refresh';

  @override
  String get catalogsOffline => 'Could not connect; the last copy is used.';

  @override
  String get catalogsInvalid =>
      'This is not a valid catalog, or it is too large; the last copy is used.';

  @override
  String get firstStepsTitle => 'First steps';

  @override
  String firstStepsCount(int done, int total) {
    return '$done / $total';
  }

  @override
  String get firstStepsLater => 'Later';

  @override
  String firstStepsResume(int done, int total) {
    return 'Continue first steps ($done / $total)';
  }

  @override
  String get firstStepDone => 'Done';

  @override
  String get firstStepAi => 'Download the answer AI';

  @override
  String get firstStepAiText =>
      'Once, on Wi-Fi. Then it answers without a signal.';

  @override
  String get firstStepAiAction => 'Go to downloads';

  @override
  String get firstStepMap => 'Download a map of your area';

  @override
  String get firstStepMapText =>
      'Nearby evacuation sites and walking routes, offline.';

  @override
  String get firstStepMapAction => 'Choose a map';

  @override
  String get firstStepSite => 'Find your nearest evacuation site on the map';

  @override
  String get firstStepSiteText => 'See how far it is on foot, while you can.';

  @override
  String get firstStepSiteAction => 'Open the map';

  @override
  String get firstStepAsk => 'Ask a first question';

  @override
  String get firstStepAskText => 'Every answer shows its sources.';

  @override
  String get firstStepAskAction => 'Pick a question';

  @override
  String get readyOffline => 'Ready offline';

  @override
  String tourStep(int n, int total) {
    return 'Tour $n / $total';
  }

  @override
  String get tourSkip => 'Skip';

  @override
  String get tourBack => 'Back';

  @override
  String get tourNext => 'Next';

  @override
  String get tourDone => 'Start';

  @override
  String get menuTour => 'Guided tour';

  @override
  String get tourStatus => 'Status';

  @override
  String get tourStatusText =>
      'Whether the app works offline, or what is still missing.';

  @override
  String get tourSite => 'Nearest evacuation site';

  @override
  String get tourSiteText =>
      'The closest site to where you are. Tap it for the way there on the map.';

  @override
  String get tourPackages => 'Installed packages';

  @override
  String get tourPackagesText =>
      'The sources answers come from. Add more for your area or activity.';

  @override
  String get tourBar => 'Ask';

  @override
  String get tourBarText =>
      'Ask in your own words. Answers work without internet and show their sources.';

  @override
  String get tourAsk => 'Questions';

  @override
  String get tourAskText =>
      'Example questions, and your past questions and answers. Kept only on this device.';

  @override
  String get tourMap => 'Map';

  @override
  String get tourMapText =>
      'Evacuation sites, expected tsunami areas and walking routes, offline.';

  @override
  String get tourMenu => 'Menu';

  @override
  String get tourMenuText =>
      'Settings, help, sharing with people nearby, and this tour.';

  @override
  String get downloadsKeepAll => 'Keep everything for phones';

  @override
  String get downloadsKeepAllHint =>
      'This computer downloads every guide and map from the catalogs and keeps them current, so phones nearby get them here. To remove items for good, turn this off.';

  @override
  String get downloadsKeepModels => 'Also the AI models (several GB)';

  @override
  String downloadsKeepAllMissing(String count, String size) {
    return 'Still to fetch: $count items, $size';
  }

  @override
  String get downloadsKeepAllDone => 'Everything is here.';

  @override
  String get helpTitle => 'Help';

  @override
  String get helpSearch => 'Search help';

  @override
  String get helpNoResults =>
      'Nothing found. Try other words, or ask in the question field.';

  @override
  String get helpAllTopics => 'All help';

  @override
  String get nearestOutsideTitle => 'You are outside this map\'s area';

  @override
  String get nearestOutsideText =>
      'Download a map of where you are, and the nearest evacuation site shows here.';

  @override
  String get stickTitle => 'USB stick';

  @override
  String get stickCopy => 'Copy to a USB stick';

  @override
  String get stickCopyHint =>
      'Everything installed here, for places without a network';

  @override
  String get stickLoad => 'Load from a USB stick';

  @override
  String stickLoadHint(String app) {
    return 'Guides, maps and models signed by $app or a publisher you added';
  }

  @override
  String get stickCopying => 'Copying to the stick…';

  @override
  String get stickLoading => 'Checking and installing…';

  @override
  String stickCopied(String added, String notNewer, String path) {
    return '$added items copied, $notNewer already there ($path)';
  }

  @override
  String stickLoaded(String added, String notNewer, String notTrusted) {
    return '$added new, $notNewer not newer than here, $notTrusted not trusted';
  }

  @override
  String stickFailedItems(String items) {
    return 'Not done (files missing or changed): $items';
  }

  @override
  String get stickNoCatalog => 'There is no Lychnion folder on this stick.';

  @override
  String stickFailed(String detail) {
    return 'Could not finish: $detail';
  }

  @override
  String get stickBusy =>
      'Wait until the downloads have finished, then load from the stick.';

  @override
  String stickUnreadable(String reason) {
    return 'The Lychnion folder on this stick cannot be read ($reason). Nothing was changed.';
  }

  @override
  String get aboutVersion => 'Version';

  @override
  String aboutVersionValue(String version, String build) {
    return '$version (build $build)';
  }

  @override
  String get aboutData => 'Installed data';

  @override
  String get aboutCopyHint => 'Long press to copy (for reports)';

  @override
  String get aboutCopied => 'Copied';
}
