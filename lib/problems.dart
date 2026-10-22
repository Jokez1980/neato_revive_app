/// Human-readable texts for robot error and alert codes.
/// Same wording as the Vacuula web app (app/src/i18n/locales/en.json).
const robotProblems = <String, String>{
  // Gen3
  'gen_picked_up': 'Put me down on the floor',
  'dustbin_full': 'Dust bin full - please empty it',
  'dustbin_missing': 'Dust bin missing - put it back in',
  'nav_backdrop_wheelextended': 'Clear my path',
  'maint_brush_stuck': 'Clean my brush',
  'maint_brush_overload': 'Clean my brush',
  'maint_bumper_stuck': 'Free my bumper',
  'maint_left_wheel_stuck': 'Clean my left wheel',
  'maint_right_wheel_stuck': 'Clean my right wheel',
  'maint_brush_change': 'Time to check the brush - it might need replacing',
  // Gen4
  'brush_change': 'Time to replace the brush',
  'bumper_stuck': 'Bumper stuck - check it moves freely',
  'picked_up': 'The robot was lifted - put it back on the floor',
  'brush_overload': 'Brush overloaded - check for tangles',
  'main_brush_overcurrent': 'Main brush overloaded - check for tangles',
  'main_brush_stuck': 'Main brush stuck - check for tangles',
  'side_brush_overcurrent': 'Side brush overloaded - check for tangles',
  'navigation_undocking_failed': "Couldn't leave the base",
  'navigation_falling': 'Close to a drop - move the robot away',
  'navigation_backdrop_leftbump': 'Too close to an edge - move the robot away',
  'navigation_backdrop_frontbump': 'Too close to an edge - move the robot away',
  'navigation_backdrop_wheelextended': 'Too close to an edge - move the robot away',
  'navigation_rightdrop_leftbump': 'Drop detected - move the robot away from the edge',
  'navigation_no_exits_to_go': 'The robot is trapped - clear a way out',
  'navigation_path_problems_returning_home': 'Having trouble finding the way to the base',
  'navigation_no_progress': "The robot isn't making progress - check for obstacles",
  'navigation_path_blocked_going_to_zone': 'The way to the zone is blocked',
  'lw_hanging': 'Left wheel hanging',
  'rw_hanging': 'Right wheel hanging',
};

/// "maint_brush_stuck, dustbin_full" -> "Clean my brush; Dust bin full - please empty it"
String problemText(String codes) => codes.split(', ').map((c) {
      final known = robotProblems[c];
      if (known != null) return known;
      var t = c;
      for (final p in ['ui_error_', 'ui_alert_', 'maint_', 'nav_', 'gen_']) {
        if (t.startsWith(p)) t = t.substring(p.length);
      }
      t = t.replaceAll('_', ' ');
      return t.isEmpty ? c : t[0].toUpperCase() + t.substring(1);
    }).join('; ');
