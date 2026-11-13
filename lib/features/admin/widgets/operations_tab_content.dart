import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../department/screens/department_management_screen.dart';
import '../../dental/screens/dental_lab_screen.dart';
import '../../eye/screens/eye_surgery_screen.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../inventory/screens/purchase_order_list_screen.dart';
import '../../vendors/screens/vendor_management_screen.dart';
import '../../whatsapp/widgets/whatsapp_requests_view.dart';

/// Combined operations content providing tab switching between Inventory, Departments, Vendors, Purchase Orders, Dental Lab, Eye Surgery, and WhatsApp Requests.
class OperationsTabContent extends StatefulWidget {
  const OperationsTabContent({
    super.key,
    this.initialTab = 0,
  });

  /// 0 = Inventory, 1 = Departments, 2 = Vendors, 3 = Purchase Orders, 4 = Dental Lab, 5 = Eye Surgery, 6 = WhatsApp Requests
  final int initialTab;

  @override
  State<OperationsTabContent> createState() => _OperationsTabContentState();
}

class _OperationsTabContentState extends State<OperationsTabContent> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  Widget _buildMobileTabItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryContainer.withValues(alpha: 0.15)
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.outlineVariant,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sub-navigation bar
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 768.0;
              if (isDesktop) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment<int>(
                            value: 0,
                            label: Text('Inventory'),
                            icon: Icon(Icons.inventory_2_outlined, size: 16),
                          ),
                          ButtonSegment<int>(
                            value: 1,
                            label: Text('Departments'),
                            icon: Icon(Icons.business_outlined, size: 16),
                          ),
                          ButtonSegment<int>(
                            value: 2,
                            label: Text('Vendors'),
                            icon: Icon(Icons.local_shipping_outlined, size: 16),
                          ),
                          ButtonSegment<int>(
                            value: 3,
                            label: Text('Purchase Orders'),
                            icon: Icon(Icons.receipt_long_outlined, size: 16),
                          ),
                          ButtonSegment<int>(
                            value: 4,
                            label: Text('Dental Lab'),
                            icon: Icon(Icons.biotech_outlined, size: 16),
                          ),
                          ButtonSegment<int>(
                            value: 5,
                            label: Text('Eye Surgery'),
                            icon: Icon(Icons.visibility_outlined, size: 16),
                          ),
                          ButtonSegment<int>(
                            value: 6,
                            label: Text('WhatsApp Requests'),
                            icon: Icon(Icons.chat_bubble_outline, size: 16),
                          ),
                        ],
                        selected: {_selectedTab},
                        onSelectionChanged: (newSelection) {
                          setState(() => _selectedTab = newSelection.first);
                        },
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor:
                              AppColors.primaryContainer.withValues(alpha: 0.2),
                          selectedForegroundColor: AppColors.primary,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Mobile compact grid: all destinations visible
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildMobileTabItem(
                        index: 0,
                        label: 'Inventory',
                        icon: Icons.inventory_2_outlined,
                      ),
                      const SizedBox(width: 6),
                      _buildMobileTabItem(
                        index: 1,
                        label: 'Departments',
                        icon: Icons.business_outlined,
                      ),
                      const SizedBox(width: 6),
                      _buildMobileTabItem(
                        index: 2,
                        label: 'Vendors',
                        icon: Icons.local_shipping_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildMobileTabItem(
                        index: 3,
                        label: 'Purchase Orders',
                        icon: Icons.receipt_long_outlined,
                      ),
                      const SizedBox(width: 6),
                      _buildMobileTabItem(
                        index: 4,
                        label: 'Dental Lab',
                        icon: Icons.biotech_outlined,
                      ),
                      const SizedBox(width: 6),
                      _buildMobileTabItem(
                        index: 5,
                        label: 'Eye Surgery',
                        icon: Icons.visibility_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildMobileTabItem(
                        index: 6,
                        label: 'WhatsApp Requests',
                        icon: Icons.chat_bubble_outline,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        // Body content based on selected tab
        Expanded(
          child: _selectedTab == 0
              ? const InventoryManagementContent()
              : _selectedTab == 1
                  ? const DepartmentManagementContent()
                  : _selectedTab == 2
                      ? const VendorManagementContent()
                      : _selectedTab == 3
                          ? const PurchaseOrderManagementContent()
                          : _selectedTab == 4
                              ? const DentalLabContent()
                              : _selectedTab == 5
                                  ? const EyeSurgeryScreen()
                                  : const WhatsAppRequestsView(),
        ),
      ],
    );
  }
}
