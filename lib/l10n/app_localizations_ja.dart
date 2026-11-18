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
  String get downloadsErrorTaken =>
      'この ID かファイル名がほかの発行元からインストール済みのため、インストールしませんでした。';

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
  String get mapBaseHint => 'ベース：✎で避難所の状況を入力。地図を長押しで通行止め・給水を登録。';

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
  String answerBaseComputer(String name) {
    return 'ベース · $name';
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
  String get settingsBase => 'ベース';

  @override
  String settingsKeptAside(String files) {
    return '保存データの一部を使えませんでした。コピーを残しました：$files';
  }

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
  String get askPhaseBase => 'ベース';

  @override
  String get askPhaseServing => '公開中';

  @override
  String get askPhaseFailed => '利用できません';

  @override
  String get askExplainNoModel => '「設定」→「ダウンロード」でAIモデルと資料を取得してください。';

  @override
  String get askExplainLoading => 'この端末でAIモデルを読み込んでいます。';

  @override
  String get askExplainReady => 'AIはこの端末の中で動いています。インターネットは不要です。';

  @override
  String get askExplainBase => '近くのベース（パソコン）が、同じWi-Fiで回答します。この端末より速く答えます。';

  @override
  String get askExplainServing =>
      'この端末が、同じWi-Fiのスマートフォンからの質問に答え、資料・地図と最新の情報を共有しています。設定から止められます。';

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
  String get baseNoAddress => 'ネットワークのアドレスがありません。この端末をWi-Fiに接続してください。';

  @override
  String get baseConnectPhones => 'スマートフォンを接続';

  @override
  String baseScanHint(String appName, String name) {
    return '同じWi-Fiにつないだスマートフォンのカメラで読み取ると、$appNameが開き「$name」に接続します。';
  }

  @override
  String get baseOrEnterAddress => 'またはアドレスを入力：';

  @override
  String baseConnectTo(String name) {
    return '$nameに接続しますか？';
  }

  @override
  String get baseThisBase => 'このベース';

  @override
  String baseConnectBody(String address) {
    return 'ベース（$address）が質問に答え、最新の情報を共有します。いま居る場所のコードだけを読み取ってください。';
  }

  @override
  String get baseConnect => '接続';

  @override
  String get baseAddress => 'ベースのアドレス';

  @override
  String get baseAddressHelper => 'ベースのQRコードの横に表示されています。';

  @override
  String get baseConnectComputer => 'ベースに接続';

  @override
  String get baseConnectComputerHint => 'ベースのQRコードを読み取るか、アドレスを入力します。回答が速くなります。';

  @override
  String baseAskedFirst(String address) {
    return '先にこちらに質問 · $address';
  }

  @override
  String get baseDisconnect => '切断';

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
      'Wi-Fi につながっていません。データ通信量を使います。多くの料金プランでは Wi-Fi のほうが安くすみます。近くにベースがあれば、その Wi-Fi からもダウンロードできます。';

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
  String get webError => 'ベースが回答できませんでした。もう一度お試しください。';

  @override
  String get baseWithApp => 'アプリで';

  @override
  String get baseInBrowser => 'ブラウザで';

  @override
  String get baseBrowserHint =>
      'アプリがないスマートフォン用：このコンピューターのページが開きます。質問と回答は同じ Wi-Fi の中だけでやりとりします。';

  @override
  String get shareOnNetwork => 'この端末をベースにする';

  @override
  String get shareOnNetworkHint =>
      '同じWi-Fiのスマホから、このコンピューターに質問したり、資料や地図をダウンロードしたりできます。';

  @override
  String get shareName => 'ベースの名前';

  @override
  String get shareNameHint => 'スマホに表示されます（例：南小学校 避難所、〇〇山荘）';

  @override
  String get shareStarting => '準備ができしだい公開します。';

  @override
  String get shareShowLarge => '大きく表示';

  @override
  String get shareNearby => '近くの人に共有';

  @override
  String get shareNearbyIntro =>
      '同じWi-Fiやテザリングにつないだスマートフォンで、このQRコードを読み取ると、このスマートフォンにダウンロードした資料・地図・モデルを受け取れます。インターネットは要りません。';

  @override
  String get shareNearbyKeepOpen => 'この画面を開いている間だけ共有します。その間、画面は消えません。';

  @override
  String get shareNearbyNothing =>
      'まだダウンロードしたものがありません。共有できるのは、ダウンロードした資料・地図・モデルです。';

  @override
  String shareNearbyItems(int count) {
    return '共有中：$count件';
  }

  @override
  String shareNearbySent(int count) {
    return '送信済み：$countファイル';
  }

  @override
  String get shareNearbyNoNetwork =>
      'Wi-Fiにつながっていません。両方のスマートフォンを同じWi-Fiかテザリングにつないでください。';

  @override
  String get shareReceiveTitle => '近くのスマートフォンから受け取りますか？';

  @override
  String shareReceiveBody(String address) {
    return '$address にある資料・地図・モデルを、ダウンロード画面に表示します。署名を確認してから保存します。';
  }

  @override
  String get shareReceiveShow => '表示';

  @override
  String get shareReceiveNone => '受け取れるものが見つかりませんでした。同じWi-Fiにつながっているか確認してください。';

  @override
  String shareReceiveFound(int count) {
    return '$count件を受け取れます';
  }

  @override
  String get shareReceiveNothingNew => '新しいものはありません。このスマートフォンにはすべてそろっています。';

  @override
  String get answerBaseUnreachable =>
      'ベースにつながらず、この端末にも回答モデルがありません。ベースと同じWi-Fiにつないでから、もう一度お試しください。';

  @override
  String get shareNearbyHint => 'ダウンロードした資料・地図・モデルを、近くのスマートフォンに渡します';

  @override
  String get settingsRegion => '地域';

  @override
  String get regionAuto => '自動（現在地から）';

  @override
  String regionAutoIs(String name) {
    return '自動：$name';
  }

  @override
  String get regionUnknown => '現在地がわかりません（日本として扱います）';

  @override
  String regionManual(String name) {
    return '$name（手動で選択）';
  }

  @override
  String get regionHint => 'その地域の資料を少し優先します。位置情報はこの端末の外に出ません。';

  @override
  String get regionJapan => '日本（都道府県を指定しない）';

  @override
  String get areaJapan => '日本';

  @override
  String get publishersTitle => '発行元';

  @override
  String get publishersHint => 'インストールするガイドと地図に署名できる発行元';

  @override
  String get publishersBuiltIn => 'アプリに組み込み';

  @override
  String publishersAddedOn(String date) {
    return '$date に追加';
  }

  @override
  String publishersKey(String id) {
    return '鍵 $id';
  }

  @override
  String get publishersRemove => '削除';

  @override
  String publishersRemoveTitle(String name) {
    return '$name を削除しますか？';
  }

  @override
  String get publishersRemoveBody =>
      'この発行元のガイドと地図は、この端末から削除されます。もう一度使うには、発行元を追加し直してダウンロードしてください。';

  @override
  String get publishersAddTitle => 'この発行元を追加しますか？';

  @override
  String publishersAddBody(String app) {
    return '知っている発行元（お住まいの市など）だけを追加してください。追加すると、$appはその発行元が署名したガイドと地図を、自身のものと同じようにインストールします。';
  }

  @override
  String get publishersAdd => '追加';

  @override
  String publishersAdded(String name) {
    return '$name を追加しました';
  }

  @override
  String get publishersFromLink => 'リンクから追加';

  @override
  String get publishersLinkLabel => '発行元のリンク';

  @override
  String get publishersNotALink => '発行元のリンクではありません。';

  @override
  String get publishersBadName => 'リンクの発行元名が正しくありません。';

  @override
  String get publishersBadKey => 'リンクの鍵が正しくありません。';

  @override
  String publishersBuiltInName(String name) {
    return '$name はアプリに組み込まれているため、追加できません。';
  }

  @override
  String publishersOtherKey(String name) {
    return '$name は別の鍵で追加済みです。発行元が鍵を変えた場合は、先に削除してください。';
  }

  @override
  String publishersKnown(String name) {
    return '$name は追加済みです。';
  }

  @override
  String get publishersSaveFailed => '発行元の一覧を保存できませんでした。変更はありません。';

  @override
  String get publishersNone =>
      'ほかの発行元はまだありません。独自のガイドを発行する市や団体から、追加用のリンクか QR コードを受け取れます。';

  @override
  String get publishTitle => '自分で発行';

  @override
  String get publishIntro =>
      '市や団体のガイドと地図をスマートフォンに届けます。署名の鍵はこのパソコンに残ります。スマートフォンはあなたのコードを読み取ると、あなたのパッケージを信頼します。';

  @override
  String get publishName => '発行元名（例：jp.city.kobe）';

  @override
  String get publishNameHelp => '小文字の英字・数字・ドット・ハイフン。あとから変更できません。';

  @override
  String get publishDisplayName => '表示名（例：神戸市）';

  @override
  String get publishCreate => '発行元の鍵を作成';

  @override
  String get publishBadName => '小文字の英字・数字・ドット・ハイフンを使ってください。「lychnion」は使えません。';

  @override
  String publishKeyNote(String path) {
    return '鍵は $path に保存されています。オフラインで控えを保管してください。失うと、スマートフォンで新しい鍵を追加し直す必要があります。';
  }

  @override
  String get publishScanHint => 'スマートフォンでこのコードを読み取ると、あなたのガイドと地図を信頼します。';

  @override
  String get publishCopyLink => 'リンクをコピー';

  @override
  String get publishLinkCopied => 'リンクをコピーしました';

  @override
  String get publishPick => 'ガイドか地図を発行';

  @override
  String get publishKindPackage => 'ガイド';

  @override
  String get publishKindMap => '地図';

  @override
  String get publishId => 'ID';

  @override
  String get publishVersion => '版（例：2026.11.1）';

  @override
  String get publishTitleJa => 'タイトル（日本語）';

  @override
  String get publishTitleEn => 'タイトル（英語）';

  @override
  String get publishLicence => 'ライセンスと出典';

  @override
  String get publishSign => '署名して発行';

  @override
  String publishDone(String name, String version) {
    return '$name $version を発行しました';
  }

  @override
  String get publishPublished => 'このパソコンで発行したもの';

  @override
  String get publishNothing => 'まだ発行したものはありません。';

  @override
  String get publishNotPackage => 'パッケージファイルではありません。';

  @override
  String get publishErrorId => 'ID には英字・数字・ドット・ハイフン・アンダースコアだけを使えます。';

  @override
  String get publishErrorVersion => '版はドット区切りの数字にしてください（例：2026.11.1）。';

  @override
  String publishErrorOlder(String have) {
    return '版 $have は発行済みかインストール済みです。より大きい版にしてください。';
  }

  @override
  String get publishErrorFiles => 'ファイル名はすべて「ID.」で始まる必要があります。ガイドは1ファイルです。';

  @override
  String get publishErrorMeta => 'ID と版はパッケージファイルと一致させてください。';

  @override
  String publishErrorTaken(String publisher) {
    return 'この ID は $publisher からインストール済みです。別の ID にしてください。';
  }

  @override
  String get publishErrorTitle => 'タイトルを入力してください。';

  @override
  String get publishErrorKey => 'この発行元名には別の鍵が追加されています。先に「発行元」で削除してください。';

  @override
  String publishFailed(String detail) {
    return '発行できませんでした：$detail';
  }

  @override
  String publishKeyUnreadable(String path) {
    return '鍵ファイル $path を読み込めません。控えから戻してください。新しい鍵にすると、スマートフォンで発行元を追加し直す必要があります。';
  }

  @override
  String get publishKeyExists => '鍵ファイルがすでにあります。置き換えることはありません。';

  @override
  String get publishKeyPrivateFailed => '鍵ファイルを非公開にできなかったため、鍵を作成しませんでした。';

  @override
  String get catalogsTitle => 'カタログ';

  @override
  String catalogsHint(String app) {
    return '市や団体のガイドと地図の一覧（$appのものに加えて）';
  }

  @override
  String get catalogsNone =>
      'ほかのカタログはまだありません。独自のガイドを提供する市や団体から、リンクか QR コードを受け取れます。';

  @override
  String get catalogsAdd => 'カタログを追加';

  @override
  String get catalogsUrlLabel => 'カタログのアドレスかリンク';

  @override
  String get catalogsNotALink => 'カタログのアドレスではありません。';

  @override
  String get catalogsAddTitle => 'このカタログを追加しますか？';

  @override
  String catalogsAddBody(String app) {
    return 'このカタログのガイドと地図が「ダウンロード」に表示されます。表示されるのは、$appか、追加した発行元が署名したものだけです。';
  }

  @override
  String get catalogsFollow => '追加';

  @override
  String catalogsStatus(String shown, String notShown) {
    return '表示 $shown 件・非表示 $notShown 件';
  }

  @override
  String get catalogsNotShownHint =>
      '非表示：追加していない発行元のもの、署名が正しくないもの、またはほかの発行元の ID と重なるもの。';

  @override
  String catalogsFetched(String date) {
    return '$date に更新';
  }

  @override
  String get catalogsNeverFetched => 'まだ読み込んでいません';

  @override
  String catalogsError(String error) {
    return '読み込めませんでした（$error）。前回のものを使っています。';
  }

  @override
  String get catalogsRemove => '削除';

  @override
  String catalogsRemoveTitle(String name) {
    return '$name を削除しますか？';
  }

  @override
  String get catalogsRemoveBody =>
      'このカタログの項目は「ダウンロード」に表示されなくなります。インストール済みのものは残ります。';

  @override
  String get catalogsKnown => 'このカタログは追加済みか、一覧がいっぱいです。';

  @override
  String get catalogsSaveFailed => 'カタログの一覧を保存できませんでした。変更はありません。';

  @override
  String get catalogsRefresh => '更新';

  @override
  String get catalogsOffline => '接続できませんでした。前回のものを使っています。';

  @override
  String get catalogsInvalid => '正しいカタログではないか、大きすぎます。前回のものを使っています。';

  @override
  String get firstStepsTitle => 'はじめの準備';

  @override
  String firstStepsCount(int done, int total) {
    return '$done / $total';
  }

  @override
  String get firstStepsLater => 'あとで';

  @override
  String firstStepsResume(int done, int total) {
    return 'はじめの準備を続ける（$done / $total）';
  }

  @override
  String get firstStepDone => '完了';

  @override
  String get firstStepAi => '回答のための AI をダウンロード';

  @override
  String get firstStepAiText => 'Wi-Fi のあるときに一度だけ。入れておけば、電波がなくても答えられます。';

  @override
  String get firstStepAiAction => 'ダウンロードへ';

  @override
  String get firstStepMap => '地域の地図をダウンロード';

  @override
  String get firstStepMapText => '近くの避難場所と歩いて行ける道を、オフラインで。';

  @override
  String get firstStepMapAction => '地図を選ぶ';

  @override
  String get firstStepSite => '近くの避難場所を地図で確かめる';

  @override
  String get firstStepSiteText => '歩いて何分か、いまのうちに。';

  @override
  String get firstStepSiteAction => '地図を開く';

  @override
  String get firstStepAsk => '最初の質問をしてみる';

  @override
  String get firstStepAskText => '答えには、いつも出典がつきます。';

  @override
  String get firstStepAskAction => '質問を選ぶ';

  @override
  String get readyOffline => 'オフラインで使えます';

  @override
  String tourStep(int n, int total) {
    return '使い方 $n / $total';
  }

  @override
  String get tourSkip => 'スキップ';

  @override
  String get tourBack => '戻る';

  @override
  String get tourNext => '次へ';

  @override
  String get tourDone => 'はじめる';

  @override
  String get menuTour => '使い方ツアー';

  @override
  String get tourStatus => '準備の状態';

  @override
  String get tourStatusText => 'オフラインで使えるか、何が足りないかがここに出ます。';

  @override
  String get tourSite => '近くの避難場所';

  @override
  String get tourSiteText => 'いる場所から一番近い避難場所です。タップすると地図で道順を表示します。';

  @override
  String get tourPackages => '入っているパッケージ';

  @override
  String get tourPackagesText => '答えのもとになる資料です。地域や用途に合わせて追加できます。';

  @override
  String get tourBar => '質問する';

  @override
  String get tourBarText => '知りたいことを、ふだんの言葉で。インターネットがなくても答え、出典もいっしょに表示します。';

  @override
  String get tourAsk => '質問';

  @override
  String get tourAskText => '質問の例と、これまでの質問と答え。この端末の中だけに保存されます。';

  @override
  String get tourMap => '地図';

  @override
  String get tourMapText => '避難場所、津波の浸水想定、歩いて行ける道。オフラインで使えます。';

  @override
  String get tourMenu => 'メニュー';

  @override
  String get tourMenuText => '設定、ヘルプ、近くの人と共有、そしてこのツアーはここから。';

  @override
  String get downloadsKeepAll => 'スマートフォン用にすべて保管';

  @override
  String get downloadsKeepAllHint =>
      'このパソコンがカタログのすべてのガイドと地図をダウンロードし、最新に保ちます。近くのスマートフォンはここから受け取れます。項目を削除したままにするには、オフにしてください。';

  @override
  String get downloadsKeepModels => 'AI モデルも（数 GB）';

  @override
  String downloadsKeepAllMissing(String count, String size) {
    return '未取得：$count 件、$size';
  }

  @override
  String get downloadsKeepAllDone => 'すべてそろっています。';

  @override
  String get helpTitle => 'ヘルプ';

  @override
  String get helpSearch => 'ヘルプを検索';

  @override
  String get helpNoResults => '見つかりませんでした。ほかの言葉で探すか、質問欄で聞いてください。';

  @override
  String get helpAllTopics => 'すべてのヘルプ';

  @override
  String get nearestOutsideTitle => 'いる場所は、この地図の範囲外です';

  @override
  String get nearestOutsideText => 'いる場所の地図をダウンロードすると、近くの避難場所をここに表示します。';

  @override
  String get stickTitle => 'USB メモリ';

  @override
  String get stickCopy => 'USB メモリにコピー';

  @override
  String get stickCopyHint => 'ここにあるすべてを、ネットワークのない場所へ';

  @override
  String get stickLoad => 'USB メモリから読み込む';

  @override
  String stickLoadHint(String app) {
    return '$appか追加した発行元が署名したガイド・地図・モデル';
  }

  @override
  String get stickCopying => 'USB メモリにコピーしています…';

  @override
  String get stickLoading => '確認してインストールしています…';

  @override
  String stickCopied(String added, String notNewer, String path) {
    return '$added 件をコピーしました（$notNewer 件は保存済み）：$path';
  }

  @override
  String stickLoaded(String added, String notNewer, String notTrusted) {
    return '新規 $added 件、ここより新しくないもの $notNewer 件、信頼できないもの $notTrusted 件';
  }

  @override
  String stickFailedItems(String items) {
    return '完了できなかったもの（ファイルがないか変更されています）：$items';
  }

  @override
  String get stickNoCatalog => 'この USB メモリに Lychnion のフォルダがありません。';

  @override
  String stickFailed(String detail) {
    return '完了できませんでした：$detail';
  }

  @override
  String get stickBusy => 'ダウンロードが終わってから USB メモリから読み込んでください。';

  @override
  String stickUnreadable(String reason) {
    return 'この USB メモリの Lychnion フォルダを読み込めません（$reason）。何も変更していません。';
  }

  @override
  String get aboutVersion => 'バージョン';

  @override
  String aboutVersionValue(String version, String build) {
    return '$version（ビルド $build）';
  }

  @override
  String get aboutData => '入っているデータ';

  @override
  String get aboutCopyHint => '長押しでコピー（問い合わせ用）';

  @override
  String get aboutCopied => 'コピーしました';

  @override
  String stickClashed(String items) {
    return 'コピーしていません（同じ ID の別の発行元のものが USB メモリにあります）：$items';
  }

  @override
  String publishErrorPackage(String detail) {
    return 'このファイルはアプリで使えるガイドではありません（$detail）。lychnion-data のツールで作り直してください。';
  }

  @override
  String get baseFoundTitle => 'この Wi-Fi のベース';

  @override
  String get baseFoundLooking => '探しています…';

  @override
  String get baseFoundNone => 'まだ見つかりません。下にアドレスを入力するか、ベースの QR コードを読み取ってください。';

  @override
  String get baseScanToTrust => 'お知らせを信頼するには、ベースの QR コードを読み取ってください。';

  @override
  String answerReading(int count) {
    return '資料$count件を読んでいます…';
  }

  @override
  String answerTimeLeft(int seconds) {
    return 'あと約$seconds秒';
  }

  @override
  String get answerSlowPhone => 'この端末では、答えまで1分ほどかかることがあります。';

  @override
  String get answerBaseHint => 'ベースにつなぐと、数秒で答えます';

  @override
  String get answerReadyAnnounce => '回答が出ました。';

  @override
  String get answerSafetyLineSpoken => '安全のための注意';

  @override
  String menuWithUpdates(int count) {
    return 'メニューを表示（更新$count件）';
  }

  @override
  String firstStepsCountSpoken(int done, int total) {
    return '$total件中$done件完了';
  }

  @override
  String get mapLoadingSpoken => '地図を読み込んでいます';

  @override
  String baseQrSpoken(String name) {
    return '$nameにつなぐためのQRコード';
  }

  @override
  String get shareNearbyQrSpoken => 'このダウンロードを受け取るためのQRコード';

  @override
  String get publishQrSpoken => 'あなたの発行元を追加するためのQRコード';

  @override
  String mapNearestSiteSpoken(String name) {
    return '最寄りの場所：$name';
  }

  @override
  String get mapAddPointAtCentre => '長押しで、地図の中心に通行止め・給水所を登録します';

  @override
  String get answerFailedAnnounce => '今回は回答できませんでした。';
}
