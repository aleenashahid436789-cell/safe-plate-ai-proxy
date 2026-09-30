// lib/models/challenge_profile.dart

enum ChallengeGoal { weightLoss, weightGainMuscle }

enum Sex { male, female, nonBinary }

enum ActivityLevel { sedentary, lightlyActive, moderatelyActive, veryActive }

enum DietPreference { standard, vegetarian, vegan, keto, highProtein, omnivore }

enum FitnessLevel { beginner, intermediate, advanced }

extension ChallengeGoalLabel on ChallengeGoal {
  String get label => this == ChallengeGoal.weightLoss
      ? 'Weight Loss'
      : 'Weight Gain & Muscle Build';
}

extension SexLabel on Sex {
  String get label {
    switch (this) {
      case Sex.male:
        return 'Male';
      case Sex.female:
        return 'Female';
      case Sex.nonBinary:
        return 'Non-binary';
    }
  }
}

extension ActivityLevelLabel on ActivityLevel {
  String get label {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Sedentary';
      case ActivityLevel.lightlyActive:
        return 'Lightly Active';
      case ActivityLevel.moderatelyActive:
        return 'Moderately Active';
      case ActivityLevel.veryActive:
        return 'Very Active';
    }
  }
}

extension DietPreferenceLabel on DietPreference {
  String get label {
    switch (this) {
      case DietPreference.standard:
        return 'Standard';
      case DietPreference.vegetarian:
        return 'Vegetarian';
      case DietPreference.vegan:
        return 'Vegan';
      case DietPreference.keto:
        return 'Keto';
      case DietPreference.highProtein:
        return 'High Protein';
      case DietPreference.omnivore:
        return 'Omnivore';
    }
  }
}

extension FitnessLevelLabel on FitnessLevel {
  String get label {
    switch (this) {
      case FitnessLevel.beginner:
        return 'Beginner';
      case FitnessLevel.intermediate:
        return 'Intermediate';
      case FitnessLevel.advanced:
        return 'Advanced';
    }
  }
}

const List<String> equipmentOptions = [
  'Bodyweight only',
  'Dumbbells',
  'Full Gym Access',
  'Resistance Bands',
  'Kettlebell',
  'Pull-up bar',
];

/// World cuisines offered as meal-plan options.
const List<String> worldCuisines = [
  'Italian',
  'Mexican',
  'Indian',
  'Chinese',
  'Japanese',
  'Thai',
  'Korean',
  'Middle Eastern',
  'Mediterranean',
  'Greek',
  'French',
  'Spanish',
  'Vietnamese',
  'American',
  'Caribbean',
  'African (Pan-African)',
  'Ethiopian',
  'Turkish',
  'Filipino',
  'Brazilian',
  'German',
  'British',
  'Pakistani',
  'Indonesian',
];

class ChallengeProfile {
  // 1. Basic Profile
  final ChallengeGoal goal;
  final int age;
  final Sex sex;
  final double currentWeightKg;
  final double targetWeightKg;
  final double heightCm;

  // 2. Activity & Lifestyle
  final ActivityLevel activityLevel;
  final double sleepHoursAvg;
  final double waterGoalLiters;

  // 3. Diet & Nutrition Preferences
  final DietPreference dietPreference;
  final int mealFrequency;
  final List<String> allergiesOrDislikes;

  // 4. Fitness & Equipment
  final FitnessLevel fitnessLevel;
  final List<String> equipment;
  final int workoutDaysPerWeek;
  final int minutesPerWorkout;
  final String injuriesOrLimitations;

  // Cuisine preferences for the meal framework
  final List<String> favoriteCuisines;

  // User's own favorite dishes/foods — used instead of or alongside the
  // generic cuisine suggestions, portion-controlled to fit their targets.
  final List<String> favoriteDishes;

  /// 30 free days + 60 premium days = 90 total.
  final int durationDays;

  ChallengeProfile({
    required this.goal,
    required this.age,
    required this.sex,
    required this.currentWeightKg,
    required this.targetWeightKg,
    required this.heightCm,
    required this.activityLevel,
    required this.sleepHoursAvg,
    required this.waterGoalLiters,
    required this.dietPreference,
    required this.mealFrequency,
    this.allergiesOrDislikes = const [],
    required this.fitnessLevel,
    required this.equipment,
    required this.workoutDaysPerWeek,
    required this.minutesPerWorkout,
    this.injuriesOrLimitations = 'None',
    required this.favoriteCuisines,
    this.favoriteDishes = const [],
    this.durationDays = 90,
  });

  double get bmi {
    final heightM = heightCm / 100;
    return currentWeightKg / (heightM * heightM);
  }

  Map<String, dynamic> toJson() => {
        'goal': goal.label,
        'age': age,
        'sex': sex.label,
        'currentWeightKg': currentWeightKg,
        'targetWeightKg': targetWeightKg,
        'heightCm': heightCm,
        'bmi': bmi.toStringAsFixed(1),
        'activityLevel': activityLevel.label,
        'sleepHoursAvg': sleepHoursAvg,
        'waterGoalLiters': waterGoalLiters,
        'dietPreference': dietPreference.label,
        'mealFrequency': mealFrequency,
        'allergiesOrDislikes': allergiesOrDislikes,
        'fitnessLevel': fitnessLevel.label,
        'equipment': equipment,
        'workoutDaysPerWeek': workoutDaysPerWeek,
        'minutesPerWorkout': minutesPerWorkout,
        'injuriesOrLimitations': injuriesOrLimitations,
        'favoriteCuisines': favoriteCuisines,
        'favoriteDishes': favoriteDishes,
        'durationDays': durationDays,
      };

  /// Wire format for client<->server requests: uses enum `.name` (not the
  /// display `.label`) so it round-trips exactly via [fromWireJson].
  Map<String, dynamic> toWireJson() => {
        'goal': goal.name,
        'age': age,
        'sex': sex.name,
        'currentWeightKg': currentWeightKg,
        'targetWeightKg': targetWeightKg,
        'heightCm': heightCm,
        'activityLevel': activityLevel.name,
        'sleepHoursAvg': sleepHoursAvg,
        'waterGoalLiters': waterGoalLiters,
        'dietPreference': dietPreference.name,
        'mealFrequency': mealFrequency,
        'allergiesOrDislikes': allergiesOrDislikes,
        'fitnessLevel': fitnessLevel.name,
        'equipment': equipment,
        'workoutDaysPerWeek': workoutDaysPerWeek,
        'minutesPerWorkout': minutesPerWorkout,
        'injuriesOrLimitations': injuriesOrLimitations,
        'favoriteCuisines': favoriteCuisines,
        'favoriteDishes': favoriteDishes,
        'durationDays': durationDays,
      };

  static T _enumByName<T>(List<T> values, String name, T fallback) {
    for (final v in values) {
      if ((v as Enum).name == name) return v;
    }
    return fallback;
  }

  factory ChallengeProfile.fromWireJson(Map<String, dynamic> json) {
    return ChallengeProfile(
      goal: _enumByName(ChallengeGoal.values, json['goal'] as String, ChallengeGoal.weightLoss),
      age: (json['age'] as num).toInt(),
      sex: _enumByName(Sex.values, json['sex'] as String, Sex.male),
      currentWeightKg: (json['currentWeightKg'] as num).toDouble(),
      targetWeightKg: (json['targetWeightKg'] as num).toDouble(),
      heightCm: (json['heightCm'] as num).toDouble(),
      activityLevel: _enumByName(
          ActivityLevel.values, json['activityLevel'] as String, ActivityLevel.moderatelyActive),
      sleepHoursAvg: (json['sleepHoursAvg'] as num).toDouble(),
      waterGoalLiters: (json['waterGoalLiters'] as num).toDouble(),
      dietPreference: _enumByName(
          DietPreference.values, json['dietPreference'] as String, DietPreference.standard),
      mealFrequency: (json['mealFrequency'] as num).toInt(),
      allergiesOrDislikes: List<String>.from(json['allergiesOrDislikes'] as List? ?? const []),
      fitnessLevel:
          _enumByName(FitnessLevel.values, json['fitnessLevel'] as String, FitnessLevel.beginner),
      equipment: List<String>.from(json['equipment'] as List? ?? const []),
      workoutDaysPerWeek: (json['workoutDaysPerWeek'] as num).toInt(),
      minutesPerWorkout: (json['minutesPerWorkout'] as num).toInt(),
      injuriesOrLimitations: json['injuriesOrLimitations'] as String? ?? 'None',
      favoriteCuisines: List<String>.from(json['favoriteCuisines'] as List? ?? const []),
      favoriteDishes: List<String>.from(json['favoriteDishes'] as List? ?? const []),
      durationDays: (json['durationDays'] as num?)?.toInt() ?? 90,
    );
  }
}
