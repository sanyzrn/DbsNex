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
};

/// The bank behind [digits] (a card number, spaces already taken out), or null
/// when fewer than six digits are typed or the range is not on the list.
VaultBank? vaultBankFor(String digits) =>
    digits.length < 6 ? null : _bankBins[digits.substring(0, 6)];
