/// Test questions for spike 3, in Japanese and English.
///
/// [expected] lists source ids that answer the question; one of them must be
/// retrieved. An empty list means the package does not cover the question and
/// the right result is "no source".
class EvalQuestion {
  const EvalQuestion(this.text, this.expected, {this.lang = 'ja'});
  final String text;
  final List<String> expected;
  final String lang;

  bool get covered => expected.isNotEmpty;
}

const evalQuestions = <EvalQuestion>[
  // The eight spike 1 questions.
  EvalQuestion('大きな地震で揺れているとき、家の中ではまず何をすればいいですか？', ['kantei-jishin']),
  EvalQuestion('海の近くで強い揺れを感じました。津波警報はまだ出ていません。どうすればいいですか？', ['kantei-tsunami']),
  EvalQuestion('停電と断水が3日続いています。家族4人です。飲み水はどれくらい必要ですか？', ['kantei-sonae']),
  EvalQuestion('避難所に持っていくべきものを10個挙げてください。', ['kantei-sonae']),
  EvalQuestion('登山中に道に迷いました。スマホの電波がありません。どうすればいいですか？', []),
  EvalQuestion('山でクマに出会ってしまいました。どう行動すればいいですか？', []),
  EvalQuestion('バックカントリーで雪崩に巻き込まれた仲間を探すとき、最初にすることは何ですか？', ['kantei-setsugai']),
  EvalQuestion('腕から血がたくさん出ています。どう止血すればいいですか？', ['fdma-shiketsu']),
  // Paraphrases (no shared keywords with the source text).
  EvalQuestion('地震のとき、部屋の中ではどこに隠れればいいですか？', ['kantei-jishin']),
  EvalQuestion('災害に備えて家に置いておく水の量は？', ['kantei-sonae']),
  EvalQuestion('車を運転していて地震が来たらどうする？', ['kantei-jishin']),
  EvalQuestion('避難場所と避難所は何が違いますか？', ['kantei-hinan']),
  EvalQuestion('家族と連絡が取れないときに使える伝言サービスはありますか？', ['kantei-sonae']),
  EvalQuestion('屋根の雪下ろしで気をつけることは？', ['kantei-setsugai']),
  EvalQuestion('津波は一回だけですか？', ['kantei-tsunami']),
  EvalQuestion('クマに会わないために山菜採りで気をつけることは？', ['env-kuma']),
  // English.
  EvalQuestion('What should I do indoors during a strong earthquake?', [
    'kantei-jishin',
  ], lang: 'en'),
  EvalQuestion(
    'I am near the beach and felt strong shaking. There is no tsunami warning yet. What should I do?',
    ['kantei-tsunami'],
    lang: 'en',
  ),
  EvalQuestion(
    'How much drinking water should a family store for emergencies?',
    ['kantei-sonae'],
    lang: 'en',
  ),
  EvalQuestion('How do I stop heavy bleeding from an arm?', [
    'fdma-shiketsu',
  ], lang: 'en'),
  EvalQuestion('A friend was buried by an avalanche. What do we do first?', [
    'kantei-setsugai',
  ], lang: 'en'),
  EvalQuestion(
    'What is the difference between an evacuation site and an evacuation shelter?',
    ['kantei-hinan'],
    lang: 'en',
  ),
  // Not covered by the package: the right answer is "no source".
  EvalQuestion('火山が噴火したらどうすればいいですか？', []),
  EvalQuestion('熱中症の応急手当を教えてください。', []),
  EvalQuestion('マムシに噛まれたらどうすればいいですか？', []),
  EvalQuestion('台風が近づいているとき、窓の対策は？', []),
  EvalQuestion('How do I treat a snake bite?', [], lang: 'en'),
  EvalQuestion('What should I pack for a day hike?', [], lang: 'en'),
];
