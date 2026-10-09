/// Whether [question] is about the menstrual cycle — the period, ovulation,
/// fertility, pregnancy — in Persian or English.
///
/// For the on-device model, which is told to ask for the Cycle summary and
/// mostly does not: it guessed a number of days instead, or said it had no
/// access. Asked on the phone, a question this matches has the summary read
/// for it before the model is asked, so the answer does not depend on the
/// model following the protocol. Nothing leaves the phone for it, which is
/// why a word that only sometimes means the cycle ("period", "چرخه") is
/// allowed to match: a wrong guess costs a few lines of context, a missed
/// one costs the answer.
bool looksLikeCycleQuestion(String question) {
  final text = question
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('\u200c', ' ');
  return _cycleWords.any(text.contains) || _cycleEnglish.hasMatch(text);
}

const _cycleWords = [
  'پریود',
  'قاعدگی',
  'عادت ماهانه',
  'عادت ماهیانه',
  // «دوره» on its own (AI-07): «دورم دیر شده», «دوره‌ام کی میاد». It also
  // means a course or an era; a wrong guess costs a few lines here.
  'دوره',
  'دورم',
  'حیض',
  'رگل',
  'چرخه',
  'تخمک گذاری',
  'تخمکگذاری',
  'باروری',
  'بارداری',
  'حامله',
  'پی ام اس',
  'لک بینی',
  'خونریزی ماهانه',
];

final _cycleEnglish = RegExp(
  r'\b(?:period|periods|menstrua\w*|menses|cycle|ovulat\w*|fertil\w*|'
  r'pregnan\w*|pms|spotting)\b',
);
