import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// يغلّف أي جدول (DataTable) بحيث يمكن تمريره **رأسيًا وأفقيًا** معًا،
/// مع شريطي تمرير ظاهرين، ودعم السحب بالماوس/التراك باد على الويب
/// والديسكتوب (بالإضافة إلى اللمس).
class AppScrollableTable extends StatefulWidget {
  final Widget child;
  const AppScrollableTable({super.key, required this.child});

  @override
  State<AppScrollableTable> createState() => _AppScrollableTableState();
}

class _AppScrollableTableState extends State<AppScrollableTable> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
          ),
          child: Scrollbar(
            controller: _vertical,
            thumbVisibility: true,
            child: Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              notificationPredicate: (n) => n.depth == 1,
              child: SingleChildScrollView(
                controller: _vertical,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
