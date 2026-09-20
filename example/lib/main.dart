import 'package:flutter/material.dart';

import 'app.dart';

/// Full-stack example for `driver_rtlsdr` (post-0.3.0 merge of
/// `core_rtlsdr` + `widget_rtlsdr`): USB permission flow, every
/// `ChangeNotifier` controller, and the full immersive widget UI — proving
/// the three former packages now work together as one dependency. See
/// `app.dart` for the composition root.
void main() => runApp(const ExampleApp());
