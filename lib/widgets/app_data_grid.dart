import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../utils/platform_utils.dart';

/// تعريف عمود في [AppDataGrid]: العنوان والعرض (بالبكسل المنطقي).
class AppGridColumn {
  final String label;
  final double width;

  /// أعمدة الأرقام تُحاذى في المنتصف.
  final bool numeric;

  /// عنوان العمود على سطر واحد (يُصغَّر الخط إن ضاق العرض).
  final bool singleLine;

  const AppGridColumn(this.label,
      {this.width = 110, this.numeric = false, this.singleLine = false});
}

/// صف واحد: خلاياه بنفس ترتيب الأعمدة، ولون خلفية اختياري.
class AppGridRow {
  final List<Widget> cells;
  final Color? color;

  const AppGridRow({required this.cells, this.color});
}

typedef AppGridRowBuilder = AppGridRow Function(int index);

/// نص خلية قياسي (سطران كحد أقصى مع اقتطاع).
Widget gridText(String text, {bool bold = false, int maxLines = 2}) {
  return Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
  );
}

/// نص خلية على سطر واحد دائمًا (للتواريخ والأوقات): إن ضاق العرض
/// يُصغَّر الخط تلقائيًا بدل أن ينكسر على سطرين.
Widget gridOneLine(String text, {bool bold = false}) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
    ),
  );
}

/// تقدير عرض عمود حسب أطول نص فيه (العنوان أو أي قيمة).
double estimateColumnWidth(
  String label,
  Iterable<String> values, {
  double min = 64,
  double max = 280,
}) {
  var longest = label.length;
  for (final v in values) {
    if (v.length > longest) longest = v.length;
  }
  final width = longest * 8.5 + 28;
  return width.clamp(min, max).toDouble();
}

/// جدول بيانات بصف عناوين **مثبّت** أثناء التمرير الرأسي (مثل تجميد الصف
/// الأول في Excel)، مع تمرير أفقي ورأسي معًا.
///
/// - على سطح المكتب والويب (ويندوز/ماك/لينكس): يعمل التمرير بالبادة
///   المدمجة في اللابتوب (سحب بإصبعين) وعجلة الماوس في الاتجاهين معًا،
///   بما في ذلك الحركة القطرية. مع Shift تتحول عجلة الماوس إلى أفقي.
/// - على الموبايل: تمرير باللمس العادي.
///
/// يجب وضعه داخل حيّز ارتفاعه محدود (مثل Expanded).
class AppDataGrid extends StatefulWidget {
  final List<AppGridColumn> columns;
  final int rowCount;
  final AppGridRowBuilder rowBuilder;
  final double rowHeight;

  /// هامش داخلي رأسي (أعلى/أسفل) لخلايا الصفوف.
  final double cellVerticalPadding;

  /// ترتيب اختياري عند الضغط على عنوان العمود.
  final int? sortColumnIndex;
  final bool sortAscending;
  final ValueChanged<int>? onSort;

  /// ضغط اختياري على صف (يُمرَّر فهرس الصف).
  final ValueChanged<int>? onRowTap;

  const AppDataGrid({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.rowBuilder,
    this.rowHeight = 60,
    this.cellVerticalPadding = 0,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
    this.onRowTap,
  });

  @override
  State<AppDataGrid> createState() => _AppDataGridState();
}

class _AppDataGridState extends State<AppDataGrid> {
  static const double _headerHeight = 52;

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontalBody = ScrollController();
  final ScrollController _horizontalHeader = ScrollController();

  @override
  void initState() {
    super.initState();
    _horizontalBody.addListener(_syncHeader);
  }

  @override
  void dispose() {
    _horizontalBody.removeListener(_syncHeader);
    _vertical.dispose();
    _horizontalBody.dispose();
    _horizontalHeader.dispose();
    super.dispose();
  }

  /// يجعل صف العناوين يتحرك أفقيًا مع الجدول.
  void _syncHeader() {
    if (!_horizontalBody.hasClients || !_horizontalHeader.hasClients) return;
    final target = math.min(
      _horizontalBody.offset,
      _horizontalHeader.position.maxScrollExtent,
    );
    if ((_horizontalHeader.offset - target).abs() > 0.5) {
      _horizontalHeader.jumpTo(target);
    }
  }

  /// التمرير المخصص (بادة/ماوس) لأجهزة سطح المكتب فقط.
  bool get _customInput => switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.linux ||
        TargetPlatform.macOS =>
          true,
        _ => false,
      };

  /// تحريك نافذة العرض: [right] لليمين و[down] للأسفل (اتجاهات فيزيائية).
  void _moveViewport({double right = 0, double down = 0}) {
    if (right != 0 && _horizontalBody.hasClients) {
      final reversed =
          axisDirectionIsReversed(_horizontalBody.position.axisDirection);
      _jumpBy(_horizontalBody, reversed ? -right : right);
    }
    if (down != 0 && _vertical.hasClients) {
      _jumpBy(_vertical, down);
    }
  }

  void _jumpBy(ScrollController controller, double delta) {
    final position = controller.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target != position.pixels) controller.jumpTo(target);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event,
        (PointerSignalEvent resolved) {
      final scroll = resolved as PointerScrollEvent;
      var dx = scroll.scrollDelta.dx;
      var dy = scroll.scrollDelta.dy;
      if (HardwareKeyboard.instance.isShiftPressed && dx == 0) {
        dx = dy;
        dy = 0;
      }
      _moveViewport(right: dx, down: dy);
    });
  }

  /// سحب إصبعين على البادة (أو سحب الماوس/اللمس) في الاتجاهين معًا:
  /// المحتوى يتبع الإصبع، فنافذة العرض تتحرك عكس حركة الإصبع.
  void _onPanUpdate(DragUpdateDetails details) {
    _moveViewport(right: -details.delta.dx, down: -details.delta.dy);
  }

  static const BoxDecoration _headerCellDecoration = BoxDecoration(
    border: BorderDirectional(end: BorderSide(color: AppColors.border)),
  );

  static const BoxDecoration _bodyCellDecoration = BoxDecoration(
    border: BorderDirectional(
      end: BorderSide(color: AppColors.border),
      bottom: BorderSide(color: AppColors.border),
    ),
  );

  Widget _headerCell(int index, double width) {
    final column = widget.columns[index];
    final sorted = widget.sortColumnIndex == index;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: (column.singleLine || isMobileApp)
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    column.label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                    ),
                  ),
                )
              : Text(
                  column.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                  ),
                ),
        ),
        if (sorted) ...[
          const SizedBox(width: 4),
          Icon(
            widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: AppColors.primary,
          ),
        ],
      ],
    );
    final cell = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: _headerCellDecoration,
      child: content,
    );
    if (widget.onSort == null) return cell;
    return InkWell(onTap: () => widget.onSort!(index), child: cell);
  }

  Widget _bodyCell(int index, double width, Widget child) {
    return Container(
      width: width,
      padding: EdgeInsets.symmetric(
          horizontal: 10, vertical: widget.cellVerticalPadding),
      alignment: Alignment.center,
      decoration: _bodyCellDecoration,
      // أي نص داخل الخلية (حتى لو لم يمر عبر gridText) يُوسَّط.
      child: DefaultTextStyle.merge(textAlign: TextAlign.center, child: child),
    );
  }

  /// أقل عرض يتسع لعنوان العمود في سطر واحد (الحشو الأفقي + أيقونة الترتيب).
  double _headerMinWidth(int index) {
    final painter = TextPainter(
      text: TextSpan(
        text: widget.columns[index].label,
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w800,
          fontSize: 13.5,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.rtl,
    )..layout();
    final sortIcon = widget.onSort != null ? 18.0 : 0.0;
    return painter.width + 20 + sortIcon + 8;
  }

  Widget _buildRow(int index, List<double> widths) {
    final row = widget.rowBuilder(index);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widths.length; i++)
          _bodyCell(
            i,
            widths[i],
            i < row.cells.length ? row.cells[i] : const SizedBox.shrink(),
          ),
      ],
    );
    return ColoredBox(
      color: row.color ??
          (index.isOdd ? const Color(0x08000000) : Colors.transparent),
      child: widget.onRowTap == null
          ? content
          : InkWell(onTap: () => widget.onRowTap!(index), child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = widget.columns;
        // على الهاتف: عنوان العمود في سطر واحد وبنفس حجم الخط، فيُوسَّع
        // العمود تلقائيًا ليتسع للعنوان بدل نزوله لسطرين.
        final colWidths = [
          for (var i = 0; i < columns.length; i++)
            isMobileApp
                ? math.max(columns[i].width, _headerMinWidth(i))
                : columns[i].width,
        ];
        final baseWidth = colWidths.fold<double>(0, (sum, w) => sum + w);
        final available =
            constraints.maxWidth.isFinite ? constraints.maxWidth : baseWidth;
        // إذا كان مجموع الأعمدة أصغر من عرض الشاشة نوزّع المساحة الزائدة.
        final scale =
            (baseWidth > 0 && baseWidth < available) ? available / baseWidth : 1.0;
        final widths = [for (final w in colWidths) w * scale];
        final totalWidth = baseWidth * scale;

        final custom = _customInput;
        final ScrollPhysics? bodyPhysics =
            custom ? const NeverScrollableScrollPhysics() : null;

        final header = SizedBox(
          height: _headerHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              border: const Border(
                bottom: BorderSide(color: AppColors.border, width: 1.2),
              ),
            ),
            child: SingleChildScrollView(
              controller: _horizontalHeader,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: totalWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      _headerCell(i, widths[i]),
                  ],
                ),
              ),
            ),
          ),
        );

        Widget body = SingleChildScrollView(
          controller: _horizontalBody,
          scrollDirection: Axis.horizontal,
          physics: bodyPhysics,
          child: SizedBox(
            width: totalWidth,
            child: ListView.builder(
              controller: _vertical,
              physics: bodyPhysics,
              itemExtent: widget.rowHeight,
              itemCount: widget.rowCount,
              itemBuilder: (context, index) => _buildRow(index, widths),
            ),
          ),
        );

        body = Scrollbar(
          controller: _horizontalBody,
          thumbVisibility: true,
          child: body,
        );
        body = Scrollbar(
          controller: _vertical,
          thumbVisibility: true,
          notificationPredicate: (notification) => notification.depth == 1,
          child: body,
        );

        Widget grid = DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: body),
            ],
          ),
        );

        if (custom) {
          grid = Listener(
            onPointerSignal: _onPointerSignal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: _onPanUpdate,
              child: grid,
            ),
          );
        }
        return grid;
      },
    );
  }
}
