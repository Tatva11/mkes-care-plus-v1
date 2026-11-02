with open('lib/features/billing/providers/billing_provider.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''/// Metrics representation for today-only revenue on the Admin Dashboard.
class TodayRevenueMetrics {
  final double todayRevenue;
  final double yesterdayRevenue;
  final double? growthPercentage;
  final int todayTransactionsCount;
  final List<double> intradayHourlyBuckets; // 6 buckets
  final Map<String, double> paymentModeAmounts;

  const TodayRevenueMetrics({
    required this.todayRevenue,
    required this.yesterdayRevenue,
    required this.growthPercentage,
    required this.todayTransactionsCount,
    required this.intradayHourlyBuckets,
    required this.paymentModeAmounts,
  });

  bool get hasGrowth => growthPercentage != null;
}

/// Provider computing authoritative collections received today with yesterday comparison.
final todayRevenueMetricsProvider =
    FutureProvider<TodayRevenueMetrics>((ref) async {
  final repo = ref.watch(billingRepositoryProvider);
  final startYesterday = DateBoundaries.startOfYesterday();
  final endToday = DateBoundaries.startOfTomorrow();

  // Look back 14 days to capture invoices that received payments yesterday or today
  final invoices = await repo.fetchInvoicesForReports(
    startDate: startYesterday.subtract(const Duration(days: 14)),
    endDate: endToday,
  );

  double todayRev = 0.0;
  double yesterdayRev = 0.0;
  int todayCount = 0;
  final buckets = List<double>.filled(6, 0.0);
  final Map<String, double> modes = {
    'cash': 0.0,
    'upi': 0.0,
    'bank_transfer': 0.0,
    'other': 0.0,
  };

  for (final inv in invoices) {
    if (inv.isCancelled) continue;

    if (inv.payments.isNotEmpty) {
      for (final p in inv.payments) {
        final paymentDate = p.paidAt ?? p.createdAt ?? inv.createdAt;
        if (DateBoundaries.isToday(paymentDate)) {
          todayRev += p.amount;
          todayCount++;
          final bIdx = DateBoundaries.getIntradayBucketIndex(paymentDate);
          buckets[bIdx] += p.amount;

          final mode = p.paymentMode.toLowerCase();
          final key = modes.containsKey(mode) ? mode : 'other';
          modes[key] = (modes[key] ?? 0.0) + p.amount;
        } else if (DateBoundaries.isYesterday(paymentDate)) {
          yesterdayRev += p.amount;
        }
      }
    } else if (inv.amountPaid > 0) {
      // Invoices paid without separate payment lines
      if (DateBoundaries.isToday(inv.createdAt)) {
        todayRev += inv.amountPaid;
        todayCount++;
        final bIdx = DateBoundaries.getIntradayBucketIndex(inv.createdAt);
        buckets[bIdx] += inv.amountPaid;

        final mode = (inv.paymentMode ?? 'cash').toLowerCase();
        final key = modes.containsKey(mode) ? mode : 'other';
        modes[key] = (modes[key] ?? 0.0) + inv.amountPaid;
      } else if (DateBoundaries.isYesterday(inv.createdAt)) {
        yesterdayRev += inv.amountPaid;
      }
    }
  }

  double? growth;
  if (yesterdayRev > 0) {
    growth = ((todayRev - yesterdayRev) / yesterdayRev) * 100;
  }

  return TodayRevenueMetrics(
    todayRevenue: todayRev,
    yesterdayRevenue: yesterdayRev,
    growthPercentage: growth,
    todayTransactionsCount: todayCount,
    intradayHourlyBuckets: buckets,
    paymentModeAmounts: modes,
  );
});'''

replacement = '''/// Represents an individual hourly time slot for revenue tracking.
class HourlyRevenueSlot {
  final int slotIndex;
  final String label;
  final String fullLabel;
  final double amount;
  final int transactionCount;

  const HourlyRevenueSlot({
    required this.slotIndex,
    required this.label,
    required this.fullLabel,
    required this.amount,
    this.transactionCount = 0,
  });
}

/// Metrics representation for date-scoped and hourly-slot revenue on the Admin Dashboard.
class TodayRevenueMetrics {
  final DateTime? selectedDate;
  final double todayRevenue;
  final double yesterdayRevenue;
  final double? growthPercentage;
  final int todayTransactionsCount;
  final List<double> intradayHourlyBuckets; // 6 legacy buckets
  final List<HourlyRevenueSlot> hourlySlots; // 11 hourly slots for clinic operating hours
  final Map<String, double> paymentModeAmounts;

  const TodayRevenueMetrics({
    this.selectedDate,
    required this.todayRevenue,
    required this.yesterdayRevenue,
    required this.growthPercentage,
    required this.todayTransactionsCount,
    required this.intradayHourlyBuckets,
    this.hourlySlots = const [],
    required this.paymentModeAmounts,
  });

  bool get hasGrowth => growthPercentage != null;
  double get totalRevenue => todayRevenue;
  double get previousDayRevenue => yesterdayRevenue;
  int get transactionCount => todayTransactionsCount;

  List<HourlyRevenueSlot> get effectiveHourlySlots {
    if (hourlySlots.isNotEmpty) return hourlySlots;
    return List.generate(
      DateBoundaries.hourlySlotCount,
      (i) => HourlyRevenueSlot(
        slotIndex: i,
        label: DateBoundaries.hourlySlotLabels[i],
        fullLabel: DateBoundaries.hourlySlotFullLabels[i],
        amount: i < intradayHourlyBuckets.length ? intradayHourlyBuckets[i] : 0.0,
      ),
    );
  }
}

/// Selected date for the Admin Dashboard Revenue Graph (defaults to start of today).
final selectedRevenueDateProvider =
    StateProvider<DateTime>((ref) => DateBoundaries.startOfDay(DateTime.now()));

/// Family provider calculating hourly-slot revenue metrics for any given [targetDate].
final dateRevenueMetricsProvider =
    FutureProvider.family<TodayRevenueMetrics, DateTime>((ref, targetDate) async {
  final repo = ref.watch(billingRepositoryProvider);
  final normalizedTarget = DateBoundaries.startOfDay(targetDate);
  final startPrevious = DateBoundaries.startOfYesterday(normalizedTarget);
  final endTarget = DateBoundaries.startOfTomorrow(normalizedTarget);

  // Look back up to 90 days from target date to capture invoices that received payments on target date or previous date
  final invoices = await repo.fetchInvoicesForReports(
    startDate: startPrevious.subtract(const Duration(days: 90)),
    endDate: endTarget,
  );

  double targetRev = 0.0;
  double prevRev = 0.0;
  int targetCount = 0;
  final legacyBuckets = List<double>.filled(6, 0.0);
  final hourlyAmounts = List<double>.filled(DateBoundaries.hourlySlotCount, 0.0);
  final hourlyCounts = List<int>.filled(DateBoundaries.hourlySlotCount, 0);

  final Map<String, double> modes = {
    'cash': 0.0,
    'upi': 0.0,
    'bank_transfer': 0.0,
    'other': 0.0,
  };

  for (final inv in invoices) {
    if (inv.isCancelled) continue;

    if (inv.payments.isNotEmpty) {
      for (final p in inv.payments) {
        final paymentDate = (p.paidAt ?? p.createdAt ?? inv.createdAt).toLocal();
        if (DateBoundaries.isSameDay(paymentDate, normalizedTarget)) {
          targetRev += p.amount;
          targetCount++;

          final bIdx = DateBoundaries.getIntradayBucketIndex(paymentDate);
          legacyBuckets[bIdx] += p.amount;

          final hIdx = DateBoundaries.getHourlySlotIndex(paymentDate);
          hourlyAmounts[hIdx] += p.amount;
          hourlyCounts[hIdx]++;

          final mode = p.paymentMode.toLowerCase();
          final key = modes.containsKey(mode) ? mode : 'other';
          modes[key] = (modes[key] ?? 0.0) + p.amount;
        } else if (DateBoundaries.isSameDay(paymentDate, startPrevious)) {
          prevRev += p.amount;
        }
      }
    } else if (inv.amountPaid > 0) {
      final invDate = inv.createdAt.toLocal();
      if (DateBoundaries.isSameDay(invDate, normalizedTarget)) {
        targetRev += inv.amountPaid;
        targetCount++;

        final bIdx = DateBoundaries.getIntradayBucketIndex(invDate);
        legacyBuckets[bIdx] += inv.amountPaid;

        final hIdx = DateBoundaries.getHourlySlotIndex(invDate);
        hourlyAmounts[hIdx] += inv.amountPaid;
        hourlyCounts[hIdx]++;

        final mode = (inv.paymentMode ?? 'cash').toLowerCase();
        final key = modes.containsKey(mode) ? mode : 'other';
        modes[key] = (modes[key] ?? 0.0) + inv.amountPaid;
      } else if (DateBoundaries.isSameDay(invDate, startPrevious)) {
        prevRev += inv.amountPaid;
      }
    }
  }

  double? growth;
  if (prevRev > 0) {
    growth = ((targetRev - prevRev) / prevRev) * 100;
  }

  final slots = List.generate(
    DateBoundaries.hourlySlotCount,
    (i) => HourlyRevenueSlot(
      slotIndex: i,
      label: DateBoundaries.hourlySlotLabels[i],
      fullLabel: DateBoundaries.hourlySlotFullLabels[i],
      amount: hourlyAmounts[i],
      transactionCount: hourlyCounts[i],
    ),
  );

  return TodayRevenueMetrics(
    selectedDate: normalizedTarget,
    todayRevenue: targetRev,
    yesterdayRevenue: prevRev,
    growthPercentage: growth,
    todayTransactionsCount: targetCount,
    intradayHourlyBuckets: legacyBuckets,
    hourlySlots: slots,
    paymentModeAmounts: modes,
  );
});

/// Default provider watching the currently selected revenue date (defaults to today).
final todayRevenueMetricsProvider = FutureProvider<TodayRevenueMetrics>((ref) {
  final selectedDate = ref.watch(selectedRevenueDateProvider);
  return ref.watch(dateRevenueMetricsProvider(selectedDate).future);
});'''

assert target in text or target.replace('\n', '\r\n') in text, 'target not found in billing_provider.dart'
if target in text:
    text = text.replace(target, replacement)
else:
    text = text.replace(target.replace('\n', '\r\n'), replacement.replace('\n', '\r\n'))

with open('lib/features/billing/providers/billing_provider.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated billing_provider.dart successfully!')

