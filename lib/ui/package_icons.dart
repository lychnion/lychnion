import 'package:flutter/material.dart';

/// Icon names a package manifest may use ("icon", and each suggestion's
/// "icon"). Icons must be known at build time (Flutter keeps only the icons
/// the app names); an unknown name shows a book.
const _icons = <String, IconData>{
  'health_and_safety': Icons.health_and_safety_rounded,
  'hiking': Icons.hiking_rounded,
  'medical_services': Icons.medical_services_outlined,
  'downhill_skiing': Icons.downhill_skiing_rounded,
  'sailing': Icons.sailing_rounded,
  'waves': Icons.waves_rounded,
  'healing': Icons.healing_rounded,
  'water_drop': Icons.water_drop_outlined,
  'forest': Icons.forest_outlined,
  'thunderstorm': Icons.thunderstorm_outlined,
  'bug': Icons.bug_report_outlined,
  'volcano': Icons.volcano_outlined,
  'snow': Icons.ac_unit_rounded,
  'fire': Icons.local_fire_department_outlined,
  'map': Icons.map_outlined,
  'book': Icons.menu_book_rounded,
};

IconData packageIcon(String name) => _icons[name] ?? Icons.menu_book_rounded;
