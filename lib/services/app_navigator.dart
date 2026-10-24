import 'package:flutter/foundation.dart';

/// طلب انتقال من مكان بعيد (مثل ورقة الإشعارات) إلى شاشة أخرى. تستمع إليه الشاشة الرئيسية.
class NavRequest {
  const NavRequest.record(String id)
      : entryId = id,
        conversationId = null,
        messageId = null;
  const NavRequest.chat(String conversation, {String? message})
      : entryId = null,
        conversationId = conversation,
        messageId = message;

  final String? entryId;
  final String? conversationId;
  final String? messageId;

  bool get isRecord => entryId != null;
}

class AppNavigator extends ChangeNotifier {
  AppNavigator._();
  static final AppNavigator instance = AppNavigator._();

  NavRequest? _pending;

  void request(NavRequest r) {
    _pending = r;
    notifyListeners();
  }

  NavRequest? take() {
    final r = _pending;
    _pending = null;
    return r;
  }
}
