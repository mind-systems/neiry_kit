import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'neiry_service_provider.dart';

final rrProvider = StreamProvider<RRInterval>((ref) {
  return ref.watch(neiryServiceProvider).rrStream;
});
