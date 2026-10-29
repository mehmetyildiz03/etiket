import 'package:flutter/widgets.dart';
import 'photo_scan.dart';

// Web keeps its existing private browser camera; desktop keeps picker fallback.
bool supported(PhotoSourceService photos) => false;
Future<ScanPhoto?> capture(BuildContext context, PhotoSourceService photos) async => null;
