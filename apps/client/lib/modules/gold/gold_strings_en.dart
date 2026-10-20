/// The English half of Gold Check's words. The Persian half lives beside
/// it in `gold_strings_fa.dart`; `gold_strings.dart` holds them together,
/// and the module kit's test holds the two maps to the same keys.
library;

const Map<String, String> goldStringsEn = {
  'draftLoadError': 'Could not read the saved draft. Try again before editing.',

  'discardDraft': 'Clear this draft',

  'breakdownProfit_metalAndMaking':
      'Seller profit ({pct} of gold value + making): {amount}',
  'breakdownProfit_metalOnly': 'Seller profit ({pct} of gold value): {amount}',
  'breakdownProfit_services':
      'Seller profit ({pct} of making + commission): {amount}',
  'breakdownVatBaseNoCommission':
      'VAT base (making + profit; commission excluded by your choice): {amount}',

  'saveError':
      'Could not save your draft. Your changes are still here; try again.',
  'profitBase': 'Profit is calculated on',
  'profitBase_metalAndMaking': 'Gold value + making charge',
  'profitBase_metalOnly': 'Gold value only',
  'profitBase_services': 'Making charge + commission',
  'commissionTaxable': 'Include commission in VAT base',
  'commissionTaxableHint':
      'Match the invoice explicitly. This is a manual assumption, not a legal check.',
  'diffPercentUnavailable': 'Percentage unavailable for this rounded estimate',
  'loadError': 'Could not load saved estimates. Try again.',
  'retry': 'Try again',

  'title': 'Gold Check',
  'tagline': 'See what the asked price is made of',
  'about':
      'An auditable calculator for new gold jewelry in Iran: weight, '
      'fineness, rate, making charge, profit and VAT, line by line, with '
      'the numbers you entered kept apart from the numbers it worked out.',
  'point1': 'Line-by-line receipt',
  'point2': 'Your numbers, your formula',
  'point3': 'Saved estimates keep their day’s rates',

  // ---------------------------------------------------------- screen
  'newEstimate': 'New estimate',
  'savedQuotes': 'Saved estimates',
  'savedQuotesEmpty':
      'Nothing saved yet. Work out an estimate and keep it, together with '
      'the rates that went into it.',
  'openSavedQuotesTip': 'Saved estimates',
  'openGuideTip': 'How it works',
  'showToman': 'Toman',
  'showRial': 'Rial',
  'unitToggleSemantics': 'Unit amounts are shown in',
  'required': 'This one is needed.',
  'panelPiece': 'The piece',
  'panelRate': 'The rate',
  'panelCharges': 'Making charge, profit and tax',
  'panelExtras': 'Extras and the quoted total',
  'fixFields': 'Fill the marked fields to see the estimate.',

  // ------------------------------------------------------------ input
  'weight': 'Net gold weight',
  'weightHint':
      'Grams, up to 3 decimals — 0.001 g is one «soot». Gold only: '
      'stones, gems and other parts do not belong here.',
  'weightSuffix': 'g',
  'grossWeight': 'Gross weight (optional)',
  'grossWeightHint':
      'The whole piece with stones and non-gold parts, if the shop named '
      'it. It is only ever shown as excluded mass, never priced.',
  'fineness': 'Fineness',
  'finenessHint': '750 = 18 karat. 875 = 21k, 916 = 22k, 999 = 24k.',
  'finenessCustom': 'Custom (parts per thousand)',
  'rate': 'Price per gram (toman)',
  'rateHint':
      'The rate you were given, at the fineness you pick below. Nothing is '
      'fetched for you.',
  'rateRef': 'The rate’s own fineness',
  'rateRefHint':
      'What the entered rate is quoted for. When it differs from the '
      'piece, the rate is converted by the purity ratio — and shown, never '
      'applied silently.',
  'rateConverted':
      'Rate converted to {ppt} for this piece: {rate} per gram '
      '(ratio {ratio}).',
  'making': 'Making charge',
  'makingModePercent': '% of metal value',
  'makingModePerGram': 'Per gram',
  'makingModeFixed': 'Fixed for this piece',
  'makingModeMixed': '% + per gram',
  'makingPercentLabel': 'Making %',
  'makingPerGramLabel': 'Making per gram (toman)',
  'makingFixedLabel': 'Making, fixed (toman)',
  'profit': 'Seller profit',
  'profitHint': 'Starts at 7% — editable, not a legal cap. Shops differ; ask.',
  'vat': 'VAT',
  'vatDated': '1405 reference',
  'vatHint':
      'Starts at the 10% that is the 1405 reference on making charge, '
      'profit and commission. Editable — the rule of the day is yours to '
      'check.',
  'vatBaseNote':
      'VAT base: making + profit + commission. The metal value is not '
      'taxed in this reference case.',
  'commission': 'Commission (toman, optional)',
  'commissionHint':
      'Only if the seller named one. Counts toward the VAT base and the '
      'total.',
  'extras': 'Separately priced extras',
  'extrasHint':
      'Stones, leather, a box — anything on its own line. Their tax is '
      'not modelled here; the invoice must match.',
  'extraLabel': 'What',
  'extraAmount': 'Amount (toman)',
  'addExtra': 'Add an extra',
  'removeExtraTip': 'Remove this extra',
  'shopQuote': 'Seller’s quoted total (toman, optional)',
  'shopQuoteHint':
      'From the counter or the invoice. Shown as a difference to verify, '
      'never as a verdict.',
  'quoteTitle': 'Title',
  'shop': 'Shop',
  'quoteDate': 'Quote date',
  'quoteDateHint': 'Type the day as YYYY-MM-DD, or pick it from the calendar.',
  'dateBadFormat': 'Write it as YYYY-MM-DD.',
  'dateNotReal': 'That date does not exist.',
  'notes': 'Notes',
  'backToCalculator': 'Back to the calculator',

  // ---------------------------------------------------------- budget
  'tomanWord': 'toman',
  'rialWord': 'rials',
  'budgetTip': 'From a budget',
  'budgetTitle': 'From a budget',
  'budgetAbout':
      'How much gold does an amount buy? This runs the calculator the other way, with the rate, purity, charges, profit and VAT already entered. The weight in the form is not used.',
  'budgetField': 'Budget (toman)',
  'budgetBad': 'Write the budget as a number.',
  'budgetNone': 'Even the smallest piece costs more than this budget.',
  'budgetResult': 'About {weight} g at most fits in {amount}.',
  'budgetAtCap':
      'Any weight this calculator takes (up to {weight} g) fits in {amount}.',
  'budgetNote':
      'The same formula, run the other way. A shop that rounds differently can differ by a little.',
  'budgetUse': 'Use this weight',
  'budgetNeedsRate':
      'Enter the rate first — the budget is turned into a weight with it.',
  'makingShare': 'The making charge comes to {pct} of the metal value.',
  'copyBreakdown': 'Copy the estimate',
  'breakdownCopied': 'Estimate copied.',

  // ---------------------------------------------------------- receipt
  'receipt': 'Estimate',
  'receiptUnitToman': 'Amounts are shown in toman.',
  'receiptUnitRial': 'Amounts are shown in rials.',
  'lineMetal': 'Metal value',
  'lineMaking': 'Making charge',
  'lineProfit': 'Seller profit',
  'lineCommission': 'Commission',
  'lineVatBase': 'Taxable service subtotal',
  'lineVat': 'VAT ({pct})',
  'lineExtras': 'Separately priced extras',
  'lineTotal': 'Estimated total',
  'lineDiff': 'Difference to verify',
  'diffExplainer': 'seller’s quote − estimate',
  'nonGoldLine': '{amount} g of non-gold mass is excluded from the pricing.',
  'extrasTaxNote':
      'Tax on the extras is not modelled — the invoice must match.',
  'vatZeroNote': 'VAT is 0% because you set it to 0%.',
  'receiptSemantics': 'Cost receipt, {total}',

  // -------------------------------------------------------- breakdown
  'breakdownTitle': 'Cost breakdown (plain text)',
  'breakdownHint':
      'Select the breakdown to copy with your device’s selection menu.',
  'breakdownMetal': 'Metal value ({weight} g × {rate} toman/g): {amount}',
  'breakdownMakingPercent': 'Making charge ({pct} of metal): {amount}',
  'breakdownMakingPerGram':
      'Making charge ({rate} toman/g × {weight} g): {amount}',
  'breakdownMakingFixed': 'Making charge (fixed): {amount}',
  'breakdownMakingMixed': 'Making charge ({pct} + {rate} toman/g): {amount}',
  'breakdownProfit': 'Seller profit ({pct} of metal + making): {amount}',
  'breakdownCommission': 'Commission: {amount}',
  'breakdownVatBase':
      'Taxable service subtotal (making + profit + commission): {amount}',
  'breakdownVat': 'VAT ({pct} of the subtotal): {amount}',
  'breakdownExtra': 'Extra — {label}: {amount}',
  'breakdownTotal': 'Estimated total: {amount}',
  'breakdownQuote': 'Seller’s quoted total: {amount}',
  'breakdownDiff': 'Difference to verify: {amount} ({pct})',
  'breakdownDate': 'Quote date {date}, rate at {ppt} fineness.',

  // ------------------------------------------------------------- guide
  'guideTitle': 'How Gold Check works',
  'howTitle': 'How this is calculated',
  'howBody1':
      'Metal value = net weight × the rate at the piece’s own fineness. A '
      'rate entered for a different fineness is converted by the purity '
      'ratio, and the conversion is shown on the receipt.',
  'howBody2':
      'The making charge is the formula you picked: a percentage of the '
      'metal value, an amount per gram, a fixed amount for the piece, or '
      'a percentage plus a per-gram amount together.',
  'howBody3':
      'Seller profit uses the base you choose: gold value + making, gold value only, or making + commission. The default is the first. Commission is included only when you enter it.',
  'howBody4':
      'VAT applies to making + profit + commission by default. You may explicitly exclude commission to match the invoice. The gold itself stays outside the reference VAT base; this is a manual estimate, not a legal check.',
  'howBody5':
      'The estimated total adds it all up, plus the extras you entered. '
      'Each line is rounded to the nearest rial after it is worked out, '
      'and lines are added after rounding.',
  'disclaimerTitle': 'What this is not',
  'disclaimerBody':
      'No gold rate is fetched and no invoice is verified — every number '
      'here is one you entered. The 10% VAT and 7% profit are editable '
      'starting points dated to 1405 (2026); they are not a promise about '
      'any particular shop, invoice or year.',
  'scopeNote':
      'For new jewelry only. Second-hand gold, coins and bullion have '
      'their own spreads and rules — not modelled here, and no claim is '
      'made about them.',
  'checklistTitle': 'Ask for these on the invoice',
  'checklistNote': 'A missing line is a question, not an accusation.',
  'check1': 'Net gold weight, in soot or grams',
  'check2': 'Fineness (for example 750)',
  'check3': 'Price per gram — and which fineness it is for',
  'check4': 'The making charge and its method',
  'check5': 'Seller profit percentage',
  'check6': 'Service commission, if any',
  'check7': 'VAT base and VAT rate',
  'check8': 'Stones and extras, each on its own line',
  'check9': 'The final total',

  // ------------------------------------------------------------ quotes
  'saveQuote': 'Save estimate',
  'updateQuote': 'Update saved estimate',
  'saveSheetTitle': 'Save this estimate',
  'quoteSaved': 'Estimate saved',
  'quoteSaveFailed':
      'Could not save — the estimate stays on screen. Try again.',
  'deleteQuoteTitle': 'Delete this estimate?',
  'deleteQuoteBody':
      'The whole estimate, with the rates of its day, goes away. Undo '
      'stays available for a few seconds.',
  'quoteDeleted': 'Estimate deleted',
  'quoteRestored': 'Estimate restored',
  'openInCalculator': 'Open in calculator',
  'compare': 'Compare',
  'comparePick':
      'Pick two estimates with the same weight and fineness to compare '
      'them line by line.',
  'compareWarn':
      'These two are not on the same weight and fineness basis — the '
      'comparison may mean nothing.',
  'compareSame': 'Same weight and fineness basis.',
  'compareDifference': 'Difference',
  'savedOn': 'Saved {when}',
  'quoteDated': 'Quote date {date}',
  'whenToday': 'today',
  'whenYesterday': 'yesterday',
  'whenDaysAgo': '{n} days ago',
  'whenDate': 'on {date}',

  // ---------------------------------------------------------- problems
  // The fields put their own problems into words (parse_* below); only the
  // custom-fineness dialog needs a range sentence, because its field is a
  // bare number with no label of its own.
  'problem_fineness': 'Fineness: between 100 and 999 parts per thousand.',
  'parse_invalid': 'Numbers only: digits and one decimal point.',
  'parse_tooManyDecimals': 'Too many decimal places.',
  'parse_negative': 'A negative amount is not meaningful here.',
  'parse_tooBig': 'Too large.',
};
