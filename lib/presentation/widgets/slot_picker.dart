import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/services/availability_service.dart';
import 'app_widgets.dart';

/// أقصى مدى يقبله `getAvailability` في طلب واحد (`MAX_AVAILABILITY_RANGE_DAYS`).
const int _maxRangeDays = 31;

/// يتيح للشاشة الأم إعادة تحميل التوفّر — تُستدعى بعد `slot-unavailable`.
class SlotPickerController extends ChangeNotifier {
  int _refreshToken = 0;
  int get refreshToken => _refreshToken;

  /// يُعيد تحميل التوفّر من الخادم.
  void refresh() {
    _refreshToken++;
    notifyListeners();
  }
}

/// اختيار يوم ثم خانة زمنية، اعتماداً على `getAvailability` وحدها.
///
/// يشترك فيه مساران: الحجز الجديد وإعادة الجدولة — فلا يفترق ما يراه المريض
/// بينهما، ولا تتكرّر أخطاء التوفّر في مكانين.
///
/// كل خانة تُعرض بحالتها الحقيقية من الخادم (متاح / مكتمل / انتهى / مغلق)
/// بدل إخفاء غير المتاح: رؤية أن العاشرة ممتلئة معلومة مفيدة للمريض، بينما
/// اختفاؤها بلا تفسير يبدو عطلاً.
class SlotPicker extends StatefulWidget {
  const SlotPicker({
    super.key,
    required this.doctorId,
    required this.onSlotSelected,
    this.controller,
    this.selectedSlot,
    this.excludeSlotId,
    this.horizonDays = 30,
  });

  final String doctorId;
  final ValueChanged<AvailabilitySlot?> onSlotSelected;
  final SlotPickerController? controller;
  final AvailabilitySlot? selectedSlot;

  /// خانة تُستثنى من الاختيار — الخانة الحالية عند إعادة الجدولة.
  final String? excludeSlotId;

  final int horizonDays;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  final AvailabilityService _service = AvailabilityService();

  AvailabilityResult? _result;
  bool _isLoading = true;
  String? _selectedDate;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onRefreshRequested);
    _load();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onRefreshRequested);
    super.dispose();
  }

  @override
  void didUpdateWidget(SlotPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doctorId != widget.doctorId) {
      _selectedDate = null;
      _load();
    }
  }

  void _onRefreshRequested() => _load();

  static String _fmt(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final today = DateTime.now();
    final days = widget.horizonDays.clamp(1, _maxRangeDays);
    final result = await _service.fetch(
      doctorId: widget.doctorId,
      dateFrom: _fmt(today),
      dateTo: _fmt(today.add(Duration(days: days))),
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _isLoading = false;
      if (result.isSuccess) {
        // اليوم المختار يبقى إن كان ما زال يحمل خانات؛ وإلا ننتقل لأول يوم
        // فيه خانة قابلة للحجز بدل عرض يوم فارغ.
        final stillValid = _selectedDate != null &&
            (result.forDate(_selectedDate!)?.hasBookableSlots ?? false);
        if (!stillValid) {
          _selectedDate = result.firstBookableDate ??
              (result.days.keys.isNotEmpty ? result.days.keys.first : null);
        }
      }
    });

    // الخانة المختارة قد تكون امتلأت أثناء التحديث.
    final selected = widget.selectedSlot;
    if (selected != null && result.isSuccess) {
      final refreshed = result
          .forDate(selected.date)
          ?.slots
          .where((s) => s.slotId == selected.slotId)
          .firstOrNull;
      if (refreshed == null || !refreshed.status.isBookable) {
        widget.onSlotSelected(null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: LoadingStateView(message: 'جارٍ تحميل المواعيد المتاحة…'),
      );
    }

    final result = _result;
    if (result == null || !result.isSuccess) {
      return ErrorStateView(
        message: result?.errorMessage ?? 'تعذّر تحميل المواعيد',
        onRetry: _load,
      );
    }

    if (result.days.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy,
        title: 'لا توجد مواعيد متاحة',
        message: 'هذا الطبيب لا يستقبل حجوزات في الفترة القادمة',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DateStrip(
          days: result.days,
          selectedDate: _selectedDate,
          onSelected: (date) {
            setState(() => _selectedDate = date);
            widget.onSlotSelected(null);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _SlotGrid(
          day: _selectedDate == null ? null : result.forDate(_selectedDate!),
          selectedSlot: widget.selectedSlot,
          excludeSlotId: widget.excludeSlotId,
          onSelected: widget.onSlotSelected,
        ),
      ],
    );
  }
}

/// شريط الأيام الأفقي.
class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.days,
    required this.selectedDate,
    required this.onSelected,
  });

  final Map<String, DayAvailability> days;
  final String? selectedDate;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = days.keys.toList();

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final date = dates[index];
          final day = days[date]!;
          final isSelected = date == selectedDate;
          final parsed = DateTime.parse(date);
          final hasSlots = day.hasBookableSlots;

          return Semantics(
            button: true,
            selected: isSelected,
            label: DateFormat('EEEE d MMMM', 'ar').format(parsed),
            child: InkWell(
              onTap: hasSlots ? () => onSelected(date) : null,
              borderRadius: AppRadii.field,
              child: Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadii.field,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE', 'ar').format(parsed),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      DateFormat('d').format(parsed),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : hasSlots
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      hasSlots ? '${day.bookable.length} موعد' : 'مغلق',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// شبكة خانات اليوم المختار.
class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.day,
    required this.selectedSlot,
    required this.excludeSlotId,
    required this.onSelected,
  });

  final DayAvailability? day;
  final AvailabilitySlot? selectedSlot;
  final String? excludeSlotId;
  final ValueChanged<AvailabilitySlot?> onSelected;

  @override
  Widget build(BuildContext context) {
    final current = day;
    if (current == null || current.slots.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy,
        title: 'لا مواعيد في هذا اليوم',
        message: 'اختر يوماً آخر من الشريط أعلاه',
      );
    }

    if (!current.hasBookableSlots) {
      return const EmptyState(
        icon: Icons.event_busy,
        title: 'كل مواعيد هذا اليوم محجوزة',
        message: 'اختر يوماً آخر من الشريط أعلاه',
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: current.slots.map((slot) {
        final isExcluded = slot.slotId == excludeSlotId;
        return _SlotChip(
          slot: slot,
          isSelected: selectedSlot?.slotId == slot.slotId,
          isCurrent: isExcluded,
          onTap: slot.status.isBookable && !isExcluded
              ? () => onSelected(slot)
              : null,
        );
      }).toList(),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.slot,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
  });

  final AvailabilitySlot slot;
  final bool isSelected;

  /// الخانة الحالية للموعد عند إعادة الجدولة — تُعرض ولا تُختار.
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;

    final Color background;
    final Color foreground;
    if (isSelected) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (isCurrent) {
      background = scheme.secondaryContainer;
      foreground = scheme.onSecondaryContainer;
    } else if (enabled) {
      background = scheme.surface;
      foreground = scheme.onSurface;
    } else {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.outline;
    }

    // سبب عدم الإتاحة يُقال صراحةً بدل شطب الخانة بلا تفسير.
    final String? note = isCurrent
        ? 'موعدك الحالي'
        : switch (slot.status) {
            SlotStatus.available =>
              slot.isGroupSlot ? 'باقي ${slot.remainingCapacity}' : null,
            SlotStatus.full => 'مكتمل',
            SlotStatus.past => 'انتهى',
            SlotStatus.closed => 'مغلق',
          };

    return Semantics(
      button: enabled,
      enabled: enabled,
      selected: isSelected,
      label: '${slot.displayTime}${note == null ? '' : '، $note'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.field,
        child: Container(
          constraints: const BoxConstraints(minWidth: 92, minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.field,
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                slot.displayTime,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  decoration: slot.status == SlotStatus.past
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              if (note != null)
                Text(
                  note,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: foreground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
