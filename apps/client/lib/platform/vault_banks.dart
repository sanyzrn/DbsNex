/// An Iranian bank, as its card numbers name it.
class VaultBank {
  const VaultBank(this.fa, this.en);

  final String fa;
  final String en;

  String name({required bool persian}) => persian ? fa : en;
}

/// The first six digits of a card number — its issuer identification number —
/// and the bank that issues from it.
///
/// A suggestion, never a rule: the list is what the Shetab network publishes
/// and what banks have kept, it can lag a new range, and an unknown number is
/// simply not recognised. The editor only ever offers the name and fills an
/// empty field with it; whatever the person types stays.
const _bankBins = <String, VaultBank>{
  '603799': VaultBank('بانک ملی ایران', 'Bank Melli Iran'),
  '589210': VaultBank('بانک سپه', 'Bank Sepah'),
  '627648': VaultBank('بانک توسعه صادرات', 'Export Development Bank'),
  '627961': VaultBank('بانک صنعت و معدن', 'Bank of Industry and Mine'),
  '603770': VaultBank('بانک کشاورزی', 'Keshavarzi Bank'),
  '639217': VaultBank('بانک کشاورزی', 'Keshavarzi Bank'),
  '628023': VaultBank('بانک مسکن', 'Maskan Bank'),
  '627760': VaultBank('پست بانک ایران', 'Post Bank of Iran'),
  '502908': VaultBank('بانک توسعه تعاون', 'Tosee Taavon Bank'),
  '627412': VaultBank('بانک اقتصاد نوین', 'Eghtesad Novin Bank'),
  '622106': VaultBank('بانک پارسیان', 'Parsian Bank'),
  '639194': VaultBank('بانک پارسیان', 'Parsian Bank'),
  '502229': VaultBank('بانک پاسارگاد', 'Pasargad Bank'),
  '639347': VaultBank('بانک پاسارگاد', 'Pasargad Bank'),
  '627488': VaultBank('بانک کارآفرین', 'Karafarin Bank'),
  '502910': VaultBank('بانک کارآفرین', 'Karafarin Bank'),
  '621986': VaultBank('بانک سامان', 'Saman Bank'),
  '639346': VaultBank('بانک سینا', 'Sina Bank'),
  '639607': VaultBank('بانک سرمایه', 'Sarmayeh Bank'),
  '504706': VaultBank('بانک شهر', 'Shahr Bank'),
  '502806': VaultBank('بانک شهر', 'Shahr Bank'),
  '603769': VaultBank('بانک صادرات ایران', 'Bank Saderat Iran'),
  '627353': VaultBank('بانک تجارت', 'Tejarat Bank'),
  '585983': VaultBank('بانک تجارت', 'Tejarat Bank'),
  '610433': VaultBank('بانک ملت', 'Bank Mellat'),
  '991975': VaultBank('بانک ملت', 'Bank Mellat'),
  '589463': VaultBank('بانک رفاه کارگران', 'Refah Bank'),
  '627381': VaultBank('بانک انصار', 'Ansar Bank'),
  '639370': VaultBank('بانک مهر اقتصاد', 'Mehr Eghtesad Bank'),
  '639599': VaultBank('بانک قوامین', 'Ghavamin Bank'),
  '504172': VaultBank('بانک رسالت', 'Resalat Bank'),
  '505416': VaultBank('بانک گردشگری', 'Tourism Bank'),
  '636949': VaultBank('بانک حکمت ایرانیان', 'Hekmat Iranian Bank'),
  '606373': VaultBank('بانک قرض‌الحسنه مهر ایران', 'Qarz al-Hasna Mehr Iran'),
  '628157': VaultBank('مؤسسه اعتباری توسعه', 'Etebari Tosee Institution'),
  '505785': VaultBank('بانک ایران‌زمین', 'Iran Zamin Bank'),
  '636214': VaultBank('بانک آینده', 'Ayandeh Bank'),
  '505801': VaultBank('مؤسسه اعتباری کوثر', 'Kosar Credit Institution'),
  '585947': VaultBank('بانک خاورمیانه', 'Middle East Bank'),
  '606256': VaultBank('مؤسسه اعتباری ملل', 'Melal Credit Institution'),
  '636795': VaultBank('بانک مرکزی', 'Central Bank of Iran'),
  '507677': VaultBank('مؤسسه اعتباری نور', 'Noor Credit Institution'),
  '502938': VaultBank('بانک دی', 'Dey Bank'),
  '627884': VaultBank('بانک پارسیان', 'Parsian Bank'),
  '581874': VaultBank('بانک ایران ونزوئلا', 'Iran Venezuela Bank'),
};

/// Issuers whose range is longer than six digits, because a shorter one
/// belongs to another bank: Blu issues out of Saman's 621986.
const _longBankBins = <String, VaultBank>{
  '62198618': VaultBank('بلوبانک', 'Blu Bank'),
  '62198619': VaultBank('بلوبانک', 'Blu Bank'),
};

/// The bank behind [digits] (a card number, spaces already taken out), or null
/// when fewer than six digits are typed or the range is not on the list.
VaultBank? vaultBankFor(String digits) {
  if (digits.length < 6) return null;
  if (digits.length >= 8) {
    final long = _longBankBins[digits.substring(0, 8)];
    if (long != null) return long;
  }
  return _bankBins[digits.substring(0, 6)];
}

/// A card network, as the first digits of a number name it. Not a bank:
/// worldwide there are far too many issuers to list, but the handful of
/// networks behind nearly every card are fixed by public number ranges.
enum VaultNetwork {
  visa('Visa'),
  mastercard('Mastercard'),
  amex('American Express'),
  discover('Discover'),
  unionPay('UnionPay'),
  jcb('JCB'),
  diners('Diners Club'),
  maestro('Maestro'),
  mir('Mir'),
  troy('Troy'),
  rupay('RuPay');

  const VaultNetwork(this.label);

  /// A brand name, written the same in every language.
  final String label;
}

/// The network [digits] belongs to, or null when it is not one of them.
///
/// A suggestion like the bank: it only ever labels the number. An Iranian
/// bank wins over it, because their ranges (62…, 50…, 58…) sit inside UnionPay
/// and Maestro's and a Shetab card is neither.
VaultNetwork? vaultNetworkFor(String digits) {
  if (digits.isEmpty || vaultBankFor(digits) != null) return null;
  int head(int n) => digits.length < n ? -1 : int.parse(digits.substring(0, n));
  bool within(int n, int low, int high) {
    final value = head(n);
    return value >= low && value <= high;
  }

  if (digits.startsWith('4')) return VaultNetwork.visa;
  if (within(2, 51, 55) || within(4, 2221, 2720)) {
    return VaultNetwork.mastercard;
  }
  if (digits.startsWith('34') || digits.startsWith('37')) {
    return VaultNetwork.amex;
  }
  if (within(4, 2200, 2204)) return VaultNetwork.mir;
  if (digits.startsWith('9792')) return VaultNetwork.troy;
  if (within(4, 3528, 3589)) return VaultNetwork.jcb;
  if (digits.startsWith('36') ||
      digits.startsWith('38') ||
      digits.startsWith('39') ||
      within(3, 300, 305) ||
      digits.startsWith('3095')) {
    return VaultNetwork.diners;
  }
  if (digits.startsWith('6011') ||
      within(3, 644, 649) ||
      within(6, 622126, 622925)) {
    return VaultNetwork.discover;
  }
  if (digits.startsWith('508') ||
      within(4, 6521, 6522) ||
      within(4, 6070, 6089)) {
    return VaultNetwork.rupay;
  }
  if (digits.startsWith('62')) return VaultNetwork.unionPay;
  if (digits.startsWith('65')) return VaultNetwork.discover;
  if (digits.startsWith('5018') ||
      digits.startsWith('5020') ||
      digits.startsWith('5038') ||
      digits.startsWith('5893') ||
      digits.startsWith('6304') ||
      digits.startsWith('6759') ||
      within(4, 6761, 6763)) {
    return VaultNetwork.maestro;
  }
  return null;
}
