import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/neiry_service.dart';

final neiryServiceProvider = Provider<NeiryService>((ref) {
  final s = NeiryService();
  ref.onDispose(s.dispose);
  return s;
});
