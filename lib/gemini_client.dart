// server/lib/gemini_client.dart
//
// All Gemini API calls live here, server-side only. The API key is read
// from the GEMINI_API_KEY environment variable — it is never sent to or
// read from the client.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'models/challenge_profile.dart';

const String _model = 'gemini-3.6-flash';

String get _apiKey {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    throw StateError('GEMINI_API_KEY environment variable is not set.');
  }
  return key;
}

class GeminiException implements Exception {
  final String message;
  final int statusCode;
  GeminiException(this.message, {this.statusCode = 502});
  @override
  String toString() => message;
}

Future<Map<String, dynamic>> _callGemini(
  List<Map<String, dynamic>> parts, {
  int maxOutputTokens = 8192,
}) async {
  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
  );

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': maxOutputTokens,
        'responseMimeType': 'application/json',
      },
    }),
  );

  if (response.statusCode != 200) {
    throw GeminiException(
      'Gemini request failed (${response.statusCode}): ${response.body}',
      statusCode: response.statusCode == 429 ? 429 : 502,
    );
  }

  final decoded = jsonDecode(response.body);
  final text = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'];

  if (text == null) {
    throw GeminiException('Empty response from Gemini.');
  }

  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    final cleaned =
        text.toString().replaceAll('```json', '').replaceAll('```', '').trim();
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }
}

// ---------------------------------------------------------------------
// Food photo analysis (mirrors the prompt formerly in lib/main.dart)
// ---------------------------------------------------------------------

Future<Map<String, dynamic>> analyzeFood({
  required String base64Image,
  required String mimeType,
  String medications = '',
}) async {
  final prompt = '''
Analyze this food photo and respond with ONLY valid JSON, no markdown fences, no extra text. Use exactly this structure:

{
  "ingredients": ["item1", "item2"],
  "nutrition": {
    "calories": number,
    "carbs_g": number,
    "protein_g": number,
    "fat_g": number
  },
  "risks": [
    {"ingredient": "name", "type": "Carcinogen|Blood Pressure|Thyroid|Blood Sugar", "severity": "red|orange", "explanation": "short reason"}
  ],
  "medication_interactions": [
    {"medication": "name", "explanation": "short reason", "severity": "red|orange"}
  ]
}

Risk categories to check: carcinogens (nitrates, potassium bromate, red dye 3, acrylamide, BHA/BHT), high blood pressure (sodium, MSG), thyroid concerns (raw cruciferous, unfermented soy, high iodine), blood sugar/insulin spikes (refined sugar, high glycemic ingredients).
${medications.isNotEmpty ? 'User medications: $medications. Check for food-drug interactions (e.g. grapefruit+statins, dairy+tetracycline, vitamin K+warfarin, tyramine+MAOIs). If none found, return an empty array for medication_interactions.' : 'Return an empty array for medication_interactions.'}
If no risks found, return an empty array for risks. Nutrition is a reasonable single-serving estimate based on visual portion size.
''';

  return _callGemini([
    {'text': prompt},
    {
      'inline_data': {'mime_type': mimeType, 'data': base64Image}
    },
  ], maxOutputTokens: 2048);
}

// ---------------------------------------------------------------------
// 90-day coach plan (30 free days + 60 premium days)
// ---------------------------------------------------------------------

Future<Map<String, dynamic>> generateFirstHalf(ChallengeProfile profile) async {
  return _callGemini(
    [
      {'text': _buildFirstHalfPrompt(profile)}
    ],
    maxOutputTokens: 16384,
  );
}

Future<Map<String, dynamic>> generatePremiumPlan(ChallengeProfile profile) async {
  final middle = await _callGemini(
    [
      {'text': _buildMiddlePrompt(profile)}
    ],
    maxOutputTokens: 16384,
  );
  final last = await _callGemini(
    [
      {'text': _buildLastPrompt(profile)}
    ],
    maxOutputTokens: 16384,
  );

  return {
    'mealPlanByDay': [
      ...(middle['mealPlanByDay'] as List? ?? []),
      ...(last['mealPlanByDay'] as List? ?? []),
    ],
    'progressChecks': [
      ...(middle['progressChecks'] as List? ?? []),
      ...(last['progressChecks'] as List? ?? []),
    ],
  };
}

String _profileBlock(ChallengeProfile p) {
  final cuisineList = p.favoriteCuisines.isEmpty
      ? 'open to any global cuisine'
      : p.favoriteCuisines.join(', ');
  final equipmentList = p.equipment.join(', ');
  final allergies =
      p.allergiesOrDislikes.isEmpty ? 'None' : p.allergiesOrDislikes.join(', ');
  final favoriteDishesList =
      p.favoriteDishes.isEmpty ? 'None provided' : p.favoriteDishes.join(', ');

  return '''
### 1. Basic Profile
- Primary Goal: ${p.goal.label}
- Age: ${p.age}
- Sex: ${p.sex.label}
- Current Weight: ${p.currentWeightKg} kg
- Target Weight Goal: ${p.targetWeightKg} kg
- Height: ${p.heightCm} cm (BMI ${p.bmi.toStringAsFixed(1)})

### 2. Activity & Lifestyle
- Current Activity Level: ${p.activityLevel.label}
- Daily Sleep Average: ${p.sleepHoursAvg} hours
- Water Intake Goal: ${p.waterGoalLiters} liters/day

### 3. Diet & Nutrition Preferences
- Dietary Preference: ${p.dietPreference.label}
- Daily Meal Frequency: ${p.mealFrequency} meals/day
- Food Allergies/Dislikes: $allergies
- Favorite cuisines for meal variety: $cuisineList
- User's own favorite dishes/foods to work into the plan in
  calorie-controlled portions rather than excluding them, unless they
  conflict with an allergy or the dietary preference (then note the
  conflict and suggest the closest safe swap): $favoriteDishesList

### 4. Fitness & Equipment
- Current Fitness Level: ${p.fitnessLevel.label}
- Available Equipment: $equipmentList
- Days Available to Workout: ${p.workoutDaysPerWeek} days/week
- Time per Workout: ${p.minutesPerWorkout} minutes
- Injuries or Physical Limitations: ${p.injuriesOrLimitations}
''';
}

String _buildFirstHalfPrompt(ChallengeProfile p) {
  return '''
You are acting as a certified personal AI Health Coach. Build DAYS 1-30
(the free tier) of a tailored 90-day challenge plan for the user below.
Respond ONLY with valid JSON matching the schema at the end — no markdown,
no commentary, no code fences.

${_profileBlock(p)}

### Output Requirements
1. Daily Targets: caloric target (surplus/deficit fitting the goal) and
   macro split (protein/carbs/fats in grams). Safe and realistic only.
2. Full 90-Day Roadmap: all 6 phases of 15 days each (days 1-90), title
   and focus for each — even though this call only covers days 1-30, the
   roadmap outline covers the whole journey.
3. Weekly Workout Template: a recurring weekly schedule sized to exactly
   ${p.workoutDaysPerWeek} training days, matching equipment and fitness
   level, with exercise name, sets, reps, rest time. Substitute safely
   for any injuries/limitations.
4. Daily Meals for Days 1-30: a GENUINELY UNIQUE meal set for each of the
   30 days (not a repeated template) — ${p.mealFrequency} meals/day per
   day, one concrete dish + portion per meal (not multiple options; pick
   the single best fit), rotating through the user's favorite cuisines
   for variety across the days. Respect diet preference and allergies
   strictly. Keep each dish description concise (name + portion, one
   short clause) to stay compact across 30 days.
5. Progress Checks: metrics to track at day 15 and day 30.
6. Favorite Food, Portion-Controlled: for each dish/food the user listed
   as a favorite, a calorie-controlled portion fitting their targets plus
   a one-line tip. Flag any conflict with allergy/diet preference and
   suggest a safe swap. Empty array if none listed.
7. Motivation Rival: a fictional rival matched on age, starting weight
   (${p.currentWeightKg} kg), height, and goal. First name, a short
   competitive-but-friendly tagline, a realistic week-by-week weight
   trajectory for all 13 weeks (weeks 1-13, covering the full 90 days)
   toward the target weight (${p.targetWeightKg} kg) — vary the pace
   naturally, safe realistic rates only. One punchy friendly-competitive
   line per phase (6 lines total, covering all 6 phases).

Include a short safety disclaimer (not medical advice, consult a doctor).

Respond with this exact JSON schema:
{
  "dailyTargets": {
    "calories": "integer", "adjustment": "string",
    "proteinG": "integer", "carbsG": "integer", "fatG": "integer"
  },
  "roadmap": [
    { "phase": "integer 1-6", "days": "string e.g. '1-15'", "title": "string", "focus": "string, 1-2 sentences" }
  ],
  "weeklyWorkoutTemplate": [
    { "day": "string e.g. 'Day 1'", "sessionType": "string",
      "exercises": [ { "name": "string", "sets": "integer", "reps": "string", "restSeconds": "integer" } ] }
  ],
  "mealPlanByDay": [
    { "day": "integer 1-30",
      "meals": [ { "timing": "string e.g. '7:30 AM - Breakfast'", "cuisine": "string", "dish": "string", "portion": "string" } ] }
  ],
  "progressChecks": [
    { "day": "integer, 15 or 30", "metricsToTrack": ["string", "string", "string"] }
  ],
  "favoriteDishPortions": [
    { "dish": "string", "portionGuidance": "string", "conflictNote": "string or null", "tip": "string" }
  ],
  "rival": {
    "name": "string", "tagline": "string",
    "weeklyWeights": [ { "week": "integer 1-13", "weightKg": "number" } ],
    "phaseTrashTalk": [ { "phase": "integer 1-6", "line": "string" } ]
  },
  "disclaimer": "string"
}
''';
}

String _buildMiddlePrompt(ChallengeProfile p) {
  return '''
You are acting as a certified personal AI Health Coach. This user already
has DAYS 1-30 of their 90-day plan (premium purchase just unlocked the
rest). Now generate ONLY days 31-60 (phases 3 and 4) — unique daily meals
continuing their journey, plus progress checks. Respond ONLY with valid
JSON matching the schema at the end — no markdown, no commentary, no code
fences.

${_profileBlock(p)}

### Output Requirements
1. Daily Meals for Days 31-60: a GENUINELY UNIQUE meal set for each of
   these 30 days (continuing variety, not repeating days 1-30) —
   ${p.mealFrequency} meals/day, one concrete dish + portion per meal,
   rotating through the user's favorite cuisines. Respect diet preference
   and allergies strictly. Keep each dish description concise.
2. Progress Checks: metrics to track at day 45 and day 60.

Respond with this exact JSON schema:
{
  "mealPlanByDay": [
    { "day": "integer 31-60",
      "meals": [ { "timing": "string e.g. '7:30 AM - Breakfast'", "cuisine": "string", "dish": "string", "portion": "string" } ] }
  ],
  "progressChecks": [
    { "day": "integer, 45 or 60", "metricsToTrack": ["string", "string", "string"] }
  ]
}
''';
}

String _buildLastPrompt(ChallengeProfile p) {
  return '''
You are acting as a certified personal AI Health Coach. This user already
has DAYS 1-60 of their 90-day plan. Now generate ONLY days 61-90 (phases 5
and 6) — the final stretch: unique daily meals continuing their journey,
plus final progress checks. Respond ONLY with valid JSON matching the
schema at the end — no markdown, no commentary, no code fences.

${_profileBlock(p)}

### Output Requirements
1. Daily Meals for Days 61-90: a GENUINELY UNIQUE meal set for each of
   these 30 days (continuing variety, not repeating days 1-60) —
   ${p.mealFrequency} meals/day, one concrete dish + portion per meal,
   rotating through the user's favorite cuisines. Respect diet preference
   and allergies strictly. Keep each dish description concise.
2. Progress Checks: metrics to track at day 75 and day 90.

Respond with this exact JSON schema:
{
  "mealPlanByDay": [
    { "day": "integer 61-90",
      "meals": [ { "timing": "string e.g. '7:30 AM - Breakfast'", "cuisine": "string", "dish": "string", "portion": "string" } ] }
  ],
  "progressChecks": [
    { "day": "integer, 75 or 90", "metricsToTrack": ["string", "string", "string"] }
  ]
}
''';
}
