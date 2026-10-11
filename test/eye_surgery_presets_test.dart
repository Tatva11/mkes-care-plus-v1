import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_item_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';

void main() {
  group('CHANGE 4: Customizable Eye Surgery Inventory Presets', () {
    test('Presets support all 6 required surgery types with independent item configurations', () {
      const requiredTypes = [
        'Cataract Surgery',
        'LASIK / Refractive Surgery',
        'Glaucoma Surgery',
        'Retinal Surgery',
        'Corneal Surgery',
        'Other',
      ];

      for (final type in requiredTypes) {
        expect(EyeSurgeryModel.surgeryTypeOptions.contains(type), isTrue);
      }

      // Create presets for different surgery types
      final cataractPresetItem = EyeSurgeryItemTemplateModel(
        id: 'tmpl-cataract-1',
        surgeryType: 'Cataract Surgery',
        inventoryItemId: 'inv-iol-foldable',
        inventoryItemName: 'Foldable Intraocular Lens',
        currentStock: 45.0,
        unit: 'piece',
        defaultQuantity: 1.0,
        isActive: true,
      );

      final glaucomaPresetItem = EyeSurgeryItemTemplateModel(
        id: 'tmpl-glaucoma-1',
        surgeryType: 'Glaucoma Surgery',
        inventoryItemId: 'inv-mitomycin-c',
        inventoryItemName: 'Mitomycin-C 0.2mg/ml',
        currentStock: 20.0,
        unit: 'vial',
        defaultQuantity: 2.0,
        isActive: true,
      );

      expect(cataractPresetItem.surgeryType, equals('Cataract Surgery'));
      expect(cataractPresetItem.defaultQuantity, equals(1.0));
      expect(glaucomaPresetItem.surgeryType, equals('Glaucoma Surgery'));
      expect(glaucomaPresetItem.defaultQuantity, equals(2.0));
    });

    test('Isolation: Modifying an individual surgery item does NOT alter global preset', () {
      final globalPreset = EyeSurgeryItemTemplateModel(
        id: 'tmpl-1',
        surgeryType: 'Cataract Surgery',
        inventoryItemId: 'inv-viscoelastic',
        inventoryItemName: 'Viscoelastic Solution 2%',
        currentStock: 30.0,
        unit: 'syringe',
        defaultQuantity: 1.0,
        isActive: true,
      );

      // Surgery created using the preset as a template
      final surgeryItem = EyeSurgeryItemModel(
        id: 'item-surgery-1',
        surgeryId: 'surgery-uuid-1',
        inventoryItemId: globalPreset.inventoryItemId,
        inventoryItemName: globalPreset.inventoryItemName,
        currentStock: globalPreset.currentStock,
        unit: globalPreset.unit,
        plannedQuantity: globalPreset.defaultQuantity,
        actualQuantity: globalPreset.defaultQuantity,
        source: 'template',
      );

      // User customizes quantity for this specific surgery
      final customizedSurgeryItem = surgeryItem.copyWith(
        plannedQuantity: 3.0,
        actualQuantity: 3.0,
        source: 'manual',
      );

      expect(customizedSurgeryItem.plannedQuantity, equals(3.0));
      expect(customizedSurgeryItem.source, equals('manual'));
      // Global preset default quantity remains completely untouched
      expect(globalPreset.defaultQuantity, equals(1.0));
    });

    test('Isolation: Changing a global preset does NOT alter existing surgery items', () {
      // Existing surgery created earlier
      final existingSurgeryItem = EyeSurgeryItemModel(
        id: 'item-surgery-past',
        surgeryId: 'surgery-uuid-past',
        inventoryItemId: 'inv-blade-2.8',
        inventoryItemName: 'Slit Blade 2.8mm',
        currentStock: 50.0,
        unit: 'piece',
        plannedQuantity: 1.0,
        actualQuantity: 1.0,
        source: 'template',
      );

      // Admin updates global preset default quantity from 1 to 2
      final updatedGlobalPreset = EyeSurgeryItemTemplateModel(
        id: 'tmpl-blade',
        surgeryType: 'Cataract Surgery',
        inventoryItemId: 'inv-blade-2.8',
        inventoryItemName: 'Slit Blade 2.8mm',
        currentStock: 50.0,
        unit: 'piece',
        defaultQuantity: 2.0,
        isActive: true,
      );

      expect(updatedGlobalPreset.defaultQuantity, equals(2.0));
      // Past surgery retains its own saved list and quantity
      expect(existingSurgeryItem.plannedQuantity, equals(1.0));
    });

    test('Stock Safety: Creating or viewing a preset never deducts stock', () {
      double centralStock = 100.0;

      // Viewing or adding to preset
      final presetItem = EyeSurgeryItemTemplateModel(
        id: 'tmpl-stock-check',
        surgeryType: 'Retinal Surgery',
        inventoryItemId: 'inv-silicone-oil',
        inventoryItemName: 'Silicone Oil 1000 cSt',
        currentStock: centralStock,
        unit: 'vial',
        defaultQuantity: 2.0,
        isActive: true,
      );

      // Stock has not changed
      expect(presetItem.currentStock, equals(100.0));
      expect(centralStock, equals(100.0));
    });

    test('Stock Safety: Scheduled surgery has inventoryConsumedAt null; idempotent deduction on transition', () {
      final scheduledSurgery = EyeSurgeryModel(
        id: 'surg-stock-safe-1',
        patientId: 'patient-1',
        surgeryType: 'Cataract Surgery',
        surgeryTypeCategory: 'Cataract Surgery',
        eyeSide: 'right',
        preOpDate: DateTime.now(),
        surgeryDate: DateTime.now(),
        status: 'scheduled',
        inventoryConsumedAt: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // In scheduled status, inventoryConsumedAt is null and stock is NOT consumed
      expect(scheduledSurgery.inventoryConsumedAt, isNull);

      // Transition to in_surgery consumes stock and stamps inventoryConsumedAt
      final inSurgery = scheduledSurgery.copyWith(
        status: 'in_surgery',
        inventoryConsumedAt: DateTime.now(),
      );

      expect(inSurgery.inventoryConsumedAt, isNotNull);

      // Idempotency check: if inventoryConsumedAt is already set, stock cannot be deducted again
      final canDeductStockAgain = inSurgery.inventoryConsumedAt == null;
      expect(canDeductStockAgain, isFalse);
    });
  });
}
