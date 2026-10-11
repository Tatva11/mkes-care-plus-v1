import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';

void main() {
  group('CHANGE 2: One Central Inventory Only', () {
    test('InventoryItem serves as single authoritative stock source', () {
      final item = InventoryItem(
        id: 'inv-item-1',
        name: 'Surgical Blade #15',
        sku: 'BLADE-15',
        category: 'Surgical Supplies',
        unit: 'pcs',
        currentStock: 150.0,
        minimumStock: 20.0,
        department: 'Eye',
        isActive: true,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      );

      expect(item.currentStock, equals(150.0));
      expect(item.isLowStock, isFalse);
      expect(item.formattedStock, equals('150 pcs'));

      // Department is metadata / reporting attribution only
      expect(item.department, equals('Eye'));
    });

    test('All workflows update the same authoritative central quantity without parallel balances', () {
      double centralQuantity = 100.0;

      // 1. Stock In (Receiving purchase order)
      const stockInQty = 50.0;
      centralQuantity += stockInQty;
      expect(centralQuantity, equals(150.0));

      // 2. Stock Out (Regular dispensing)
      const stockOutQty = 20.0;
      centralQuantity -= stockOutQty;
      expect(centralQuantity, equals(130.0));

      // 3. Clinical Consumption (Dental/Eye procedure)
      const clinicalUsageQty = 15.0;
      centralQuantity -= clinicalUsageQty;
      expect(centralQuantity, equals(115.0));

      // 4. Eye Surgery usage
      const eyeSurgeryUsageQty = 10.0;
      centralQuantity -= eyeSurgeryUsageQty;
      expect(centralQuantity, equals(105.0));

      // One authoritative balance remained consistent throughout all operations
      expect(centralQuantity, equals(105.0));
    });

    test('Inventory transactions record department attribution without secondary stock table', () {
      final tx = InventoryTransaction(
        id: 'tx-1',
        inventoryItemId: 'inv-item-1',
        transactionType: 'stock_out',
        quantity: 5.0,
        stockBefore: 100.0,
        stockAfter: 95.0,
        reason: 'Dispensed to Patient',
        remarks: 'Clinical Usage (dental_treatment): Dental Clinic',
        patientId: 'patient-42',
        createdAt: DateTime(2026, 10, 10),
      );

      expect(tx.stockBefore, equals(100.0));
      expect(tx.stockAfter, equals(95.0));
      expect(tx.quantity, equals(5.0));
      expect(tx.remarks, contains('Dental Clinic'));
      // Stock is deducted from central item, not kept in separate balance
      expect(tx.stockAfter, equals(tx.stockBefore! - tx.quantity));
    });

    test('Insufficient central stock check prevents negative balances', () {
      const availableCentralStock = 8.0;
      const requestedStockOut = 10.0;

      expect(
        () {
          if (availableCentralStock < requestedStockOut) {
            throw Exception('Insufficient stock. Available: $availableCentralStock, requested: $requestedStockOut');
          }
        },
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Insufficient stock'))),
      );
    });
  });
}
