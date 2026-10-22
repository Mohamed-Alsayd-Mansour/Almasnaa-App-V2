export 'browser_launcher_stub.dart'
    if (dart.library.html) 'browser_launcher_web.dart'
    if (dart.library.io) 'browser_launcher_io.dart';
