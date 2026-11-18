// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'リクニオン';

  @override
  String get settings => '設定';

  @override
  String get beforeYouStart => 'ご利用の前に';

  @override
  String get iUnderstand => 'わかりました';

  @override
  String get downloadsErrorOffline => 'インターネットに接続されていません。';

  @override
  String get downloadsErrorWifiOnly => 'Wi-Fi に接続してください（モバイルデータは設定でオフ）。';

  @override
  String get downloadsErrorNetwork => '接続が切れました。「再開」で続きから取得します。';

  @override
  String get downloadsErrorChecksum => 'ファイルが壊れていたため削除しました。もう一度ダウンロードしてください。';

  @override
  String get downloadsErrorChecksumLocal =>
      'このファイルはカタログの版と一致しません。削除してダウンロードしてください。';

  @override
  String get downloadsErrorBusy => '別のウィンドウでダウンロード中です。';

  @override
  String get downloadsErrorDiskFull => '空き容量が足りません。';

  @override
  String get downloadsErrorDisk => 'ファイルを保存できませんでした。';

  @override
  String get downloadsErrorSignature => 'Lychnion の署名がないため、インストールしませんでした。';

  @override
  String get downloadsErrorOlder => 'インストール済みより古い版のため、インストールしませんでした。';

  @override
  String downloadsLargeWarning(String size) {
    return '$size をダウンロードします。Wi-Fi で行ってください。空き容量が $size 以上必要です。途中で止まっても、続きから再開できます。';
  }

  @override
  String get cancel => 'キャンセル';

  @override
  String get downloadsDownload => 'ダウンロード';

  @override
  String get downloadsDeleteTitle => '削除しますか？';

  @override
  String downloadsDeleteBody(String title, String size) {
    return '$title（$size）を端末から削除します。オフラインでは再取得できません。';
  }

  @override
  String get delete => '削除';

  @override
  String get downloadsTitle => 'ダウンロード';

  @override
  String get downloadsWifiOnlyHint =>
      'モデルや地図は数 GB になることがあります。「確認する」では、モバイルデータでダウンロードする前に毎回確認します。';

  @override
  String get downloadsFooter =>
      'ダウンロードしたものはすべてオフラインで使えます。ファイルはチェックサム（SHA-256）で確認してから使います。';

  @override
  String get downloadsKindModels => 'モデル';

  @override
  String get downloadsKindPackages => '知識パッケージ';

  @override
  String get downloadsKindMaps => '地図';

  @override
  String get downloadsTooLargeForPhone => '多くのスマートフォンには大きすぎます。';

  @override
  String get downloadsNotDownloaded => '未ダウンロード';

  @override
  String get downloadsNoSource => 'ダウンロード元が未設定（アプリ内蔵版を使用）';

  @override
  String downloadsPaused(String done, String total) {
    return '一時停止中：$done / $total';
  }

  @override
  String get downloadsUnverified => 'ファイルあり（未確認）';

  @override
  String get downloadsInstalled => 'ダウンロード済み・確認済み';

  @override
  String downloadsUpdateAvailable(String version) {
    return '新しい版があります（端末: $version）';
  }

  @override
  String get downloadsStop => '停止';

  @override
  String get downloadsResume => '再開';

  @override
  String get downloadsUpdate => '更新';

  @override
  String get downloadsCheckFile => 'ファイルを確認';

  @override
  String get downloadsInUse => '使用中';

  @override
  String get downloadsUseModel => 'このモデルを使う';

  @override
  String get downloadsCheckingPart => '途中までのファイルを確認中…';

  @override
  String downloadsVerifying(String percent) {
    return 'チェックサムを確認中… $percent%';
  }

  @override
  String get downloadsEtaOneMinute => '残り約1分';

  @override
  String downloadsEtaMinutes(String minutes) {
    return '残り約$minutes分';
  }

  @override
  String get justNow => 'たった今';

  @override
  String minutesAgo(String minutes) {
    return '$minutes分前';
  }

  @override
  String hoursAgo(String hours) {
    return '$hours時間前';
  }

  @override
  String daysAgo(String days) {
    return '$days日前';
  }

  @override
  String get factSourceOfficialUnverified => '公式と表示・署名なし（未確認）';

  @override
  String get factSourceSensorUnverified => 'センサーと表示・署名なし（未確認）';

  @override
  String get factSourceOfficial => '公式';

  @override
  String get factSourceSensor => 'センサー';

  @override
  String get factSourceCitizen => '住民の報告・未確認';

  @override
  String shelterStatus(String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'open': '開設',
      'crowded': '混雑',
      'full': '満員',
      'closed': '閉鎖',
      'other': '$status',
    });
    return '$_temp0';
  }

  @override
  String get factRoadBlocked => '通行止め';

  @override
  String factWater(String value) {
    return '給水：$value';
  }

  @override
  String get factUnconfirmed => '未確認';

  @override
  String get factsBoxTitle => '最新の情報 · AIの回答ではありません';

  @override
  String get factsBoxRoadBlocked => '通行止め';

  @override
  String factsBoxWater(String value) {
    return '給水：$value';
  }

  @override
  String get factsBoxAddWarning => '警報・注意報を追加';

  @override
  String get factFormWarning => '警報・注意報（例：津波警報）';

  @override
  String get factFormNote => '補足（任意）';

  @override
  String get factFormValidFor => '有効時間';

  @override
  String factFormHours(String hours) {
    return '$hours時間';
  }

  @override
  String get factFormOfficial => '公式（運営者・市）';

  @override
  String get factFormResident => '住民の報告';

  @override
  String get factFormClear => '解除する';

  @override
  String get save => '保存';

  @override
  String hazardName(String hazard) {
    String _temp0 = intl.Intl.selectLogic(hazard, {
      'tsunami': '津波',
      'earthquake': '地震',
      'flood': '洪水',
      'landslide': '崖崩れ・土石流・地滑り',
      'stormSurge': '高潮',
      'fire': '大規模な火事',
      'inlandFlood': '内水氾濫',
      'volcano': '火山現象',
      'other': '$hazard',
    });
    return '$_temp0';
  }

  @override
  String hazardInSentence(String hazard) {
    String _temp0 = intl.Intl.selectLogic(hazard, {
      'tsunami': '津波',
      'earthquake': '地震',
      'flood': '洪水',
      'landslide': '崖崩れ・土石流・地滑り',
      'stormSurge': '高潮',
      'fire': '大規模な火事',
      'inlandFlood': '内水氾濫',
      'volcano': '火山現象',
      'other': '$hazard',
    });
    return '$_temp0';
  }

  @override
  String compassPoint(String point) {
    String _temp0 = intl.Intl.selectLogic(point, {
      'n': '北',
      'ne': '北東',
      'e': '東',
      'se': '南東',
      's': '南',
      'sw': '南西',
      'w': '西',
      'nw': '北西',
      'other': '$point',
    });
    return '$_temp0';
  }

  @override
  String siteHeight(String height) {
    return '海抜$height m';
  }

  @override
  String siteFlooding(String depth) {
    return '浸水想定$depth';
  }

  @override
  String siteDip(String height) {
    return '途中で海抜$height mまで下がる';
  }

  @override
  String siteWalk(String distance, String minutes) {
    return '徒歩$distance・約$minutes分';
  }

  @override
  String siteStraight(String distance, String direction) {
    return '$directionへ$distance · 直線距離';
  }

  @override
  String depthOrMore(String lo) {
    return '$lo m以上';
  }

  @override
  String depthUnder(String hi) {
    return '$hi m未満';
  }

  @override
  String depthRange(String lo, String hi) {
    return '$lo〜$hi m';
  }

  @override
  String get depthLegendUnder => '0.3 m未満';

  @override
  String depthLegendFrom(String lo) {
    return '$lo m〜';
  }

  @override
  String mapWarningFor(String city) {
    return '$cityの警報・注意報';
  }

  @override
  String get mapRoadBlockedHere => 'ここが通行止め';

  @override
  String get mapWaterHere => 'ここで給水';

  @override
  String get mapRoadBlocked => '通行止め';

  @override
  String get mapWaterPoint => '給水';

  @override
  String get mapWaterTruck => '給水車';

  @override
  String get mapWaterStation => '給水所';

  @override
  String get mapWhichHazard => 'どの災害ですか？';

  @override
  String get mapTestLocation => 'テスト用の位置';

  @override
  String mapLocationAccuracy(String meters) {
    return '現在地 ±$meters m';
  }

  @override
  String get mapNoLocationPermission => '位置情報の許可がありません';

  @override
  String get mapNoLocation => '現在地を取得できません';

  @override
  String get mapHazard => '災害の種類';

  @override
  String get mapChooseHazard => '災害の種類を選ぶ';

  @override
  String get mapAttributionSites => '避難場所：国土地理院';

  @override
  String get mapAttributionHeights => '標高：国土地理院 標高タイル';

  @override
  String get mapAttributionFlood => '津波浸水想定：国土数値情報（国土交通省）CC BY 4.0・加工';

  @override
  String get mapNearbySites => '近くの避難場所';

  @override
  String get mapAnyHazard => 'すべての災害';

  @override
  String get mapWalkingDistance => '徒歩の道のり';

  @override
  String get mapStraightLine => '直線距離';

  @override
  String get mapKeepsHigh => '高い道を優先';

  @override
  String get mapBlockedConsidered => '通行止めを考慮';

  @override
  String get mapAboutData => 'データについて';

  @override
  String get mapMyLocation => '現在地';

  @override
  String get mapShelterHint => '避難所の端末：✎で状況を入力。地図を長押しで通行止め・給水を登録。';

  @override
  String mapInFloodArea(String depth) {
    return '現在地は津波浸水想定区域内です（想定$depth）';
  }

  @override
  String get mapNearFloodArea => '現在地は津波浸水想定区域のすぐ近くです';

  @override
  String get mapOutsideFloodArea => '現在地は津波浸水想定区域の外です';

  @override
  String mapWayOut(String distance, String minutes) {
    return '区域の外まで 徒歩$distance・約$minutes分';
  }

  @override
  String get mapFloodBasis => '公表された浸水想定によります。想定を超える津波もあります。';

  @override
  String get mapExpectedDepth => '浸水の深さ（想定）';

  @override
  String mapMinutes(String minutes) {
    return '約$minutes分';
  }

  @override
  String get mapSetStatus => '状況を入力';

  @override
  String get mapAboutRoutes =>
      '距離は OpenStreetMap の道路・歩道に沿った徒歩の道のりです（分速60 m で計算）。被害や混雑、津波の高さは考慮していません。公式の情報と現地の状況に従ってください。';

  @override
  String get mapAboutHeights =>
      '津波の場合は、少し遠回りでも高い道を通り、下り坂を避ける経路を選びます。高さは地面の標高（国土地理院 標高タイル）です。津波避難ビルでは上の階へ上がってください。';

  @override
  String get mapAboutStraight => '距離は直線距離です（道のりではありません）。';

  @override
  String get mapAboutSites =>
      '指定緊急避難場所は災害の種類ごとに指定されています。指定避難所は危険が去った後に滞在する施設です。データは最新でない場合や未掲載の場合があるため、最新の状況は市町村に確認してください。';

  @override
  String get mapGsiNotes => '国土地理院 ご利用上の注意';

  @override
  String mapNoSiteWarning(String hazard, String city) {
    return '国土地理院のデータでは、$cityに$hazardの指定緊急避難場所が登録されていません。最寄りの場所は別の市町村の可能性があります。$cityのハザードマップや避難情報を確認してください。';
  }

  @override
  String answerShelterComputer(String name) {
    return '避難所のコンピューター · $name';
  }

  @override
  String get answerLooking => '資料を確認しています…';

  @override
  String get answerRelatedOnly => '資料に関連する情報はありますが、直接の答えはありません。';

  @override
  String get answerNotCovered => 'この質問に答える資料は入っていません。';

  @override
  String get answerPartlyCovered => '資料で一部しか確認できません。公的な情報も確認してください。';

  @override
  String get answerUnchecked => 'この回答は資料で確認できませんでした。';

  @override
  String get answerSources => '出典';

  @override
  String get answerBasedOn => '回答は、公的な資料の次の部分だけにもとづいています。';

  @override
  String answerOurTranslation(String appName) {
    return '$appNameによる翻訳です（公式の訳ではありません）。原文を見る';
  }

  @override
  String answerExcerpt(String appName) {
    return '※ $appNameが一部を抜き出して表示しています。';
  }

  @override
  String answerGoTo(String hazard) {
    return '$hazardの避難場所';
  }

  @override
  String answerWayOut(String distance) {
    return '浸水想定区域の外まで 徒歩$distance';
  }

  @override
  String answerSkipped(
    String site,
    String distance,
    String status,
    String age,
  ) {
    return '$site（$distance）は$status（$age）';
  }

  @override
  String answerSource(String publisher) {
    return '出典：$publisher';
  }

  @override
  String answerSourceAndMore(String publisher, String more) {
    return '出典：$publisher ほか$more件';
  }

  @override
  String get answerSafetyLine => '安全のための一文（原文のまま）';

  @override
  String answerOfficialText(String appName) {
    return '公式の原文（回答の訳は$appNameによるもので、公式の訳ではありません）：';
  }

  @override
  String get nearestEmergencySite => '近くの指定緊急避難場所';

  @override
  String nearestSiteFor(String hazard) {
    return '近くの指定緊急避難場所（$hazard）';
  }

  @override
  String get languageName => '日本語';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsLanguageDevice => '端末の設定';

  @override
  String get settingsShelter => '避難所';

  @override
  String get settingsOfflineData => 'オフラインデータ';

  @override
  String get settingsDownloadsHint => 'AIモデル・防災の資料・地図';

  @override
  String get settingsAboutGroup => 'このアプリについて';

  @override
  String settingsAboutApp(String appName) {
    return '$appNameについて';
  }

  @override
  String get settingsAboutAppHint => 'しくみ・ご注意・オープンソース';

  @override
  String get aboutTagline => 'ギリシャ語で「小さな灯り」。ネットが止まっても使えるガイドです。';

  @override
  String get aboutHowItWorks => 'しくみ';

  @override
  String get aboutOffline => 'インターネットなしで動作';

  @override
  String get aboutOfflineText => '質問への回答、地図、避難場所の検索はすべて端末の中で行います。';

  @override
  String get aboutCheckable => '出典を確認できる回答';

  @override
  String get aboutCheckableText => '回答は公的機関の資料にもとづき、出典を表示します。資料にないことには答えません。';

  @override
  String get aboutFacts => '最新の情報はAIと分けて表示';

  @override
  String get aboutFactsText => '避難所の状況や通行止めは、時刻と発信元つきでそのまま表示します。AIは書き換えません。';

  @override
  String get aboutPleaseNote => 'ご注意';

  @override
  String get aboutPrototype => '試作版';

  @override
  String get aboutPrototypeText => '研究用の試作版です。緊急時は自治体・気象庁などの公式情報に従ってください。';

  @override
  String get aboutOpenSource => 'オープンソース';

  @override
  String get aboutSourceCode => 'ソースコード';

  @override
  String get aboutSourceCodeText =>
      'だれでも中身を確認・改良できます（GNU AGPL v3）。配布する人は、利用者にソースコードを提供する義務があります。';

  @override
  String get aboutLicences => 'ライセンス';

  @override
  String get aboutLicencesText => 'アプリ、使用しているソフトウェアとフォント';

  @override
  String get aboutDeveloper => '開発者向け';

  @override
  String get aboutShowStats => '速度とメモリを表示';

  @override
  String get aboutShowStatsHint => '回答の下に表示します。';

  @override
  String get noticeAi =>
      '回答は、公的な資料をもとにAIが作ります。AIはまちがえることがあります。回答といっしょに表示する出典を確かめてください。';

  @override
  String get noticeOfficialFirst =>
      '自治体・気象庁・警察・消防の指示や、その場にいる、わかる人の判断を優先してください。';

  @override
  String get noticeNotADoctor => '医師の診察の代わりにはなりません。登山やツアーの計画を立てるためのアプリでもありません。';

  @override
  String get noticeAsk => '迷ったときは、わかる人に聞いてください。命に関わるときは119（救急・火事）、110（警察）へ。';

  @override
  String get noticeOffline => 'インターネットなしで使えるため、情報が最新とは限りません。資料にないことには答えません。';

  @override
  String get noticeAboutGuides => '入っている資料について';

  @override
  String get noticeNewGuides => '新しい資料';

  @override
  String get askHeadline => 'もしものときに、\nすぐ聞ける。';

  @override
  String get askIntro => '防災やアウトドアの公的な資料をもとに、インターネットなしで答えます。出典もいっしょに表示します。';

  @override
  String get askFirstDownload => 'はじめに：データをダウンロード';

  @override
  String get askFirstDownloadText => 'Wi-Fi のあるときに一度だけ。その後はオフラインで使えます。';

  @override
  String get askGoToDownloads => 'ダウンロードへ';

  @override
  String get askTryAsking => 'たとえば';

  @override
  String get askPhaseNoModel => '準備が必要';

  @override
  String get askPhaseLoading => '準備中…';

  @override
  String get askPhaseReady => 'オフラインで利用可';

  @override
  String get askPhaseShelter => '避難所';

  @override
  String get askPhaseServing => '避難所の端末（公開中）';

  @override
  String get askPhaseFailed => '利用できません';

  @override
  String get askExplainNoModel => '「設定」→「ダウンロード」でAIモデルと資料を取得してください。';

  @override
  String get askExplainLoading => 'この端末でAIモデルを読み込んでいます。';

  @override
  String get askExplainReady => 'AIはこの端末の中で動いています。インターネットは不要です。';

  @override
  String get askExplainShelter => '避難所のコンピューターが、施設内のWi-Fiで回答します。この端末より速く答えます。';

  @override
  String get askExplainServing => 'この端末が、施設内のスマートフォンからの質問に答え、最新の情報を共有します。';

  @override
  String get askExplainFailed => 'AIモデルを読み込めませんでした。';

  @override
  String get askHint => '質問を入力';

  @override
  String get askStop => '停止';

  @override
  String get askSend => '送信';

  @override
  String get threadsUndo => '元に戻す';

  @override
  String get threadsNoArchived => 'アーカイブした会話はありません。';

  @override
  String get threadsRecent => '最近の質問';

  @override
  String get threadsMovedBack => '元に戻しました';

  @override
  String get threadsArchived => 'アーカイブしました';

  @override
  String get threadsDeleted => '削除しました';

  @override
  String threadsSeeAll(String count) {
    return 'すべて表示（$count）';
  }

  @override
  String get threadsArchive => 'アーカイブ';

  @override
  String get threadsArchiveHint => '右にスワイプで戻す、左にスワイプで削除。';

  @override
  String threadsArchiveCount(String count) {
    return 'アーカイブ（$count）';
  }

  @override
  String get threadsAsk => '質問';

  @override
  String get threadsNone => 'まだ質問はありません。下から質問できます。';

  @override
  String get threadsSwipeHint => '右にスワイプでアーカイブ、左にスワイプで削除。';

  @override
  String get conversationTitle => '会話';

  @override
  String get packagesTitle => '答えられる分野';

  @override
  String get packagesAdd => '追加';

  @override
  String get packagesAddTooltip => '分野を追加';

  @override
  String get shelterNoAddress => 'ネットワークのアドレスがありません。この端末を施設のWi-Fiに接続してください。';

  @override
  String get shelterConnectPhones => 'スマートフォンを接続';

  @override
  String shelterScanHint(String appName, String name) {
    return '施設のWi-Fiに接続したスマートフォンのカメラで読み取ると、$appNameが開き「$name」に接続します。';
  }

  @override
  String get shelterOrEnterAddress => 'またはアドレスを入力：';

  @override
  String shelterConnectTo(String name) {
    return '$nameに接続しますか？';
  }

  @override
  String get shelterThisShelter => 'この避難所';

  @override
  String shelterConnectBody(String address) {
    return '避難所のコンピューター（$address）が質問に答え、最新の情報を共有します。いま居る避難所のコードだけを読み取ってください。';
  }

  @override
  String get shelterConnect => '接続';

  @override
  String get shelterAddress => '避難所のアドレス';

  @override
  String get shelterAddressHelper => '避難所の端末のQRコードの横に表示されています。';

  @override
  String get shelterConnectComputer => '避難所のコンピューターに接続';

  @override
  String get shelterConnectComputerHint =>
      '避難所のQRコードを読み取るか、アドレスを入力します。回答が速くなります。';

  @override
  String shelterAskedFirst(String address) {
    return '先にこちらに質問 · $address';
  }

  @override
  String get shelterDisconnect => '切断';

  @override
  String get mapNoMap => '地図がありません';

  @override
  String get mapNoMapText => 'お住まいの地域をダウンロードすると、インターネットなしで避難場所を確認できます。';

  @override
  String get mapDownloadMap => '地図をダウンロード';

  @override
  String get navHome => 'ホーム';

  @override
  String get navAsk => '質問';

  @override
  String get navMap => '地図';

  @override
  String get conversationMoveBack => '元に戻す';

  @override
  String get conversationArchive => 'アーカイブ';

  @override
  String get conversationDeleteTitle => 'この会話を削除しますか？';

  @override
  String get conversationDeleteBody => 'この端末から削除されます。';

  @override
  String downloadsMobileTitle(String size) {
    return 'モバイルデータで $size をダウンロードしますか？';
  }

  @override
  String get downloadsMobileBody =>
      'Wi-Fi につながっていません。データ通信量を使います。多くの料金プランでは Wi-Fi のほうが安くすみます。近くに避難所のコンピューターがあれば、その Wi-Fi からもダウンロードできます。';

  @override
  String get downloadsMobileData => 'モバイルデータ';

  @override
  String get downloadsMobileNever => 'Wi-Fi のみ';

  @override
  String get downloadsMobileAsk => '確認する';

  @override
  String get downloadsMobileAlways => '常に使う';

  @override
  String get downloadsFilterAll => 'すべて';

  @override
  String get downloadsFilterInstalled => 'ダウンロード済み';

  @override
  String get downloadsFilterPackages => '資料';

  @override
  String get downloadsFilterMaps => '地図';

  @override
  String get downloadsNothingHere => 'まだありません。';

  @override
  String get downloadsSettings => 'ダウンロードの設定';

  @override
  String get downloadsUpdates => '更新';

  @override
  String get downloadsUpdatesHint =>
      '資料・地図・モデルの新しい版。「自動」では Wi-Fi のときだけ自動でダウンロードします。';

  @override
  String get downloadsUpdatesAuto => '自動';

  @override
  String get downloadsUpdatesNotify => 'お知らせ';

  @override
  String get downloadsUpdatesOff => 'オフ';

  @override
  String downloadsFilterUpdates(int count) {
    return '更新（$count）';
  }

  @override
  String get downloadsSigned => '署名済み';

  @override
  String get downloadsPublisher => '発行者';

  @override
  String get downloadsSignedOn => '署名日';

  @override
  String get downloadsKey => '鍵';

  @override
  String get downloadsFilterKind => '種類';

  @override
  String get webError => '避難所のコンピューターが回答できませんでした。もう一度お試しください。';

  @override
  String get shelterWithApp => 'アプリで';

  @override
  String get shelterInBrowser => 'ブラウザで';

  @override
  String get shelterBrowserHint =>
      'アプリがないスマートフォン用：このコンピューターのページが開きます。質問と回答は避難所の Wi-Fi の中だけでやりとりします。';
}
