/// Iranian card numbers and the bank behind their first six digits.
///
/// A card number people share to be paid is 16 digits; the first six name
/// the issuer. The table below is a small, offline copy — no lookup, no
/// network — and it is deliberately conservative: a prefix it does not know
/// reads as "Bank not recognised" rather than as a guess. [cardTableChecked]
/// is the day the table was last read against a published list, so the
/// module can say how current its knowledge is.
library;

/// The day the issuer table was checked.
const cardTableChecked = '2026-11-17';

class IranianBank {
  const IranianBank(this.fa, this.en);

  final String fa;
  final String en;
}

/// Six-digit issuer prefixes → the bank they belong to.
const cardBanks = <String, IranianBank>{
  '603799': IranianBank('بانک ملی ایران', 'Bank Melli Iran'),
  '610433': IranianBank('بانک ملت', 'Bank Mellat'),
  '589210': IranianBank('بانک سپه', 'Bank Sepah'),
  '627353': IranianBank('بانک تجارت', 'Bank Tejarat'),
  '627760': IranianBank('پست بانک ایران', 'Post Bank of Iran'),
  '628023': IranianBank('بانک مسکن', 'Bank Maskan'),
  '603770': IranianBank('بانک کشاورزی', 'Bank Keshavarzi'),
  '603769': IranianBank('بانک صادرات ایران', 'Bank Saderat Iran'),
  '627412': IranianBank('بانک اقتصاد نوین', 'EN Bank'),
  '627381': IranianBank('بانک انصار', 'Ansar Bank'),
  '502229': IranianBank('بانک پاسارگاد', 'Bank Pasargad'),
  '639347': IranianBank('بانک پاسارگاد', 'Bank Pasargad'),
  '621986': IranianBank('بانک سامان', 'Saman Bank'),
  '639346': IranianBank('بانک سامان', 'Saman Bank'),
  '627884': IranianBank('بانک پارسیان', 'Parsian Bank'),
  '639607': IranianBank('بانک سرمایه', 'Bank Sarmayeh'),
  '636795': IranianBank('بانک مرکزی ایران', 'Central Bank of Iran'),
  '627872': IranianBank('بانک رفاه کارگران', 'Bank Refah Kargaran'),
  '639370': IranianBank('بانک مهر اقتصاد', 'Mehr Eqtesad Bank'),
  '627648': IranianBank('بانک توسعه صادرات', 'Export Development Bank'),
};

/// Persian and Arabic-Indic digits become Latin digits; everything that is
/// not a digit is dropped. A card written in any of the three scripts is the
/// same card.
String cardDigits(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x30 && rune <= 0x39) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Luhn's check over a 16-digit card number. A number of another length is
/// not a card this module knows, so it fails.
bool luhnOk(String digits) {
  if (digits.length != 16) return false;
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var value = digits.codeUnitAt(i) - 0x30;
    if ((digits.length - i).isEven) {
      value *= 2;
      if (value > 9) value -= 9;
    }
    sum += value;
  }
  return sum % 10 == 0;
}

/// `6037 9977 1234 5678` — groups of four, the way a card is read aloud.
String groupCard(String digits) {
  final parts = <String>[];
  for (var start = 0; start < digits.length; start += 4) {
    parts.add(digits.substring(start, (start + 4).clamp(0, digits.length)));
  }
  return parts.join(' ');
}

/// The bank behind [digits], or null when the prefix is not in the table.
IranianBank? bankOf(String digits) {
  if (digits.length < 6) return null;
  return cardBanks[digits.substring(0, 6)];
}
