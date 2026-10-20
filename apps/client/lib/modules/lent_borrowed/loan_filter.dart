import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_people.dart';

/// Which records the overview shows.
enum LoanFilter {
  all,
  dueSoon,
  overdue,
  settled;

  bool allows(LoanStanding standing) => switch (this) {
    all => true,
    dueSoon =>
      !standing.settled &&
          (standing.due.status == DueStatus.today ||
              standing.due.status == DueStatus.dueSoon),
    overdue => standing.due.status == DueStatus.overdue,
    settled => standing.settled,
  };
}

/// Whether [loan] answers a search: the person, what it was, or its note,
/// compared the way names are (case, spacing, Arabic letter forms folded).
bool loanMatches(Loan loan, String query) {
  final needle = personKey(query);
  if (needle.isEmpty) return true;
  return personKey(loan.person).contains(needle) ||
      personKey(loan.what).contains(needle) ||
      personKey(loan.note).contains(needle);
}
