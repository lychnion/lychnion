/// Fixed questions for comparing models and devices in the spike.
///
/// No retrieval yet: these show what the bare model knows and how fast it is.
/// The answers are checked by hand against official guidance.
const benchSystemInstruction =
    'あなたは日本の防災とアウトドアの安全について答えるアシスタントです。'
    '日本語で、短く、具体的に答えてください。'
    '分からないことは分からないと言ってください。'
    '命に関わる場合は、まず119番や110番への通報を勧めてください。';

const benchPrompts = <String>[
  '大きな地震で揺れているとき、家の中ではまず何をすればいいですか？',
  '海の近くで強い揺れを感じました。津波警報はまだ出ていません。どうすればいいですか？',
  '停電と断水が3日続いています。家族4人です。飲み水はどれくらい必要ですか？',
  '避難所に持っていくべきものを10個挙げてください。',
  '登山中に道に迷いました。スマホの電波がありません。どうすればいいですか？',
  '山でクマに出会ってしまいました。どう行動すればいいですか？',
  'バックカントリーで雪崩に巻き込まれた仲間を探すとき、最初にすることは何ですか？',
  '腕から血がたくさん出ています。どう止血すればいいですか？',
];
