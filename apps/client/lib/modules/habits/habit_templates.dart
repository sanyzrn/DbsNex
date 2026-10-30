import 'habit_model.dart';

/// A ready idea to start a habit from (2.4.0). It only fills the editor;
/// every field stays the person's to change. Names and units come from the
/// module's strings (`tpl_<id>`, `tplUnit_<id>`), in the reader's language.
class HabitTemplate {
  const HabitTemplate({
    required this.id,
    required this.icon,
    required this.hue,
    this.plan = HabitPlan.daily,
    this.goal = 1,
    this.target = 3,
    this.every = 2,
    this.days = const {},
  });

  final String id;
  final String icon;
  final int hue;
  final HabitPlan plan;
  final int goal;
  final int target;
  final int every;
  final Set<int> days;

  bool get counted => goal > 1;
}

/// The ideas, in the order the editor shows them.
const habitTemplates = <HabitTemplate>[
  HabitTemplate(id: 'water', icon: 'water', hue: 5, goal: 8),
  HabitTemplate(id: 'read', icon: 'book', hue: 1, goal: 20),
  HabitTemplate(id: 'walk', icon: 'walk', hue: 4),
  HabitTemplate(
    id: 'workout',
    icon: 'gym',
    hue: 2,
    plan: HabitPlan.weekly,
    target: 3,
  ),
  HabitTemplate(id: 'stretch', icon: 'stretch', hue: 0),
  HabitTemplate(id: 'language', icon: 'language', hue: 6, goal: 15),
  HabitTemplate(id: 'sleep', icon: 'sleep', hue: 1),
  HabitTemplate(id: 'screen', icon: 'screen', hue: 7),
  HabitTemplate(
    id: 'tidy',
    icon: 'tidy',
    hue: 3,
    plan: HabitPlan.every,
    every: 3,
  ),
  HabitTemplate(id: 'journal', icon: 'write', hue: 2),
];